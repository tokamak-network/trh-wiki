---

updated: 2026-05-19
sources: []
related: []
tags: [troubleshooting]
---
# op-node genesis: l1 block = 0 (SystemConfig.startBlock() uninitialized)

**Symptom**: After deploying a new L2 stack, `rollup.json` has `"genesis":{"l1":{"hash":"0x000...","number":0}}`. The op-node must replay all of Sepolia history before the L2 safe head advances, so the proposer stays stuck at "L2 safe/finalized head is at genesis (block 0)".

## Root cause

`op-node genesis l2` (in tokamak-thanos) originally resolved the L1 starting block by calling `SystemConfig.startBlock()` on-chain. However the Go deployer (`tokamak-deployer`) uses `upgradeProxyViaAdmin` — which calls `upgradeTo()` without an initializer — so `initialize()` is never called. The `START_BLOCK_SLOT` storage is therefore `0`, and `startBlock()` returns `0`.

## Fix (applied 2026-04-27)

`op-node/cmd/genesis/cmd.go` was patched to read `config.L1StartingBlockTag` from `deploy-config.json` directly, then fetch the block by hash or number from L1. The unused `systemconfig.go` helper and its test were deleted.

Commit: `1e5426d6b8` on tokamak-thanos main.

## Deployment fix procedure

When genesis.l1 = 0 is already written into a running stack, regenerate and redeploy:

1. **Regenerate genesis + rollup** (run from trh-sdk deployer):
   - Confirm `L1StartingBlockTag` in `deploy-config.json` has the correct L1 block hash.
   - Run `op-node genesis l2` with the patched binary to get a correct `rollup.json`.
   - DRB patching: new genesis may be missing DRB Regular operator allocs and DRB code-namespace bytecode. Compare alloc counts vs old genesis (should be same). If short, copy DRB operator addresses and DRB code-namespace (`0xc0d3...0060`) from old genesis.
   - Recompute `genesis.l2.hash`: run `geth init --datadir=/tmp/x <genesis.json>` and capture the logged hash.

2. **Deploy to running stack**:
   ```bash
   # Stop order: batcher → proposer → challenger → drb-* → op-node → op-geth
   docker stop <stack>-op-batcher-1 <stack>-op-proposer-1 <stack>-op-challenger-1 \
     <stack>-drb-{leader,regular-1,regular-2,regular-3}-1 <stack>-op-node-1 <stack>-op-geth-1

   # Wipe chaindata via alpine (op-geth image entrypoint prevents direct rm)
   docker run --rm -v <stack>_op-geth-data:/data alpine \
     sh -c "rm -rf /data/geth/chaindata /data/geth/lightchaindata /data/geth/nodes /data/geth/transactions.rlp /data/geth/LOCK"

   # Overwrite genesis + rollup in config volume
   docker run --rm -v trh-local-config:/config -v /tmp/regen:/src:ro alpine \
     sh -c "cp /src/genesis-patched.json /config/genesis.json && cp /src/rollup-patched.json /config/rollup.json"

   # Init geth with new genesis (MUST do before starting op-geth)
   docker run --rm --entrypoint geth \
     -v <stack>_op-geth-data:/data -v trh-local-config:/config:ro \
     tokamaknetwork/thanos-op-geth:nightly \
     init --datadir=/data /config/genesis.json

   # Restart: op-geth first, then op-node, then rest
   docker start <stack>-op-geth-1 && sleep 5
   docker start <stack>-op-node-1
   docker start <stack>-op-batcher-1 <stack>-op-proposer-1 <stack>-op-challenger-1 \
     <stack>-drb-{leader,regular-1,regular-2,regular-3}-1
   ```

3. **Verify**: `docker logs <stack>-op-node-1` should show:
   - `"completed reset of derivation pipeline" origin=...:10736294` (not 0)
   - `"Sequencer sealed block" block=...:1`
   And `docker logs <stack>-op-batcher-1` should show `"Transaction successfully published"` within ~30 seconds.

## Notes

- The op-geth image entrypoint is `geth` but the CMD form `docker run ... geth init` fails with "invalid command". Use `--entrypoint geth` instead.
- Wiping chaindata alone is insufficient if op-geth starts before `geth init` — it will write Ethereum mainnet genesis (hash `d4e567..`) to the empty datadir. Always run `geth init` before starting op-geth.
- DRB Postgres containers do not need to be reset when restarting the chain from genesis; they reconnect automatically.
