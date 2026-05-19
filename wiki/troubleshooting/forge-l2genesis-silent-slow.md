---
updated: 2026-04-18
category: troubleshooting
sources: []
related:
  - "[[tokamak-deployer-logging]]"
  - "[[thanos-deployer-analysis]]"
  - "[[l2-deploy-local]]"
tags: [troubleshooting]
---


# forge L2Genesis Step: Silent and Slow

## Problem

During local L2 deployment, after tokamak-deployer prints
`✅ All contracts deployed successfully!`, the next step — running
`forge script scripts/L2Genesis.s.sol:L2Genesis` to produce the L2 allocs
(`state-dump-<l2ChainID>.json`) — had two symptoms:

1. **Malformed progress log**, example from the actual deploy stream:
   ```
   Running forge L2Genesis.s.sol to produce state-dumpdir/app/storage/.../contracts-bedrockaddresses/app/storage/.../deployments/111551137941-addresses.jsonconfig/app/storage/.../deploy-config/111551137941.json
   ```
   Paths concatenated with no separators, so the whole line is one run-on
   string.

2. **Total silence for multiple minutes** while forge ran, followed by either
   success or a failure that returned all captured output at once. From the UI
   there was no way to tell if the process was alive.

## Root Cause

Both bugs lived in `trh-sdk/pkg/stacks/thanos/genesis_prep.go` in
`runForgeL2GenesisScript()`.

### Bug 1 — wrong zap SugaredLogger method

```go
logger.Info("Running forge L2Genesis.s.sol to produce state-dump",
    "dir", contractsDir,
    "addresses", stagedAddrPath,
    "config", stagedConfigPath)
```

`SugaredLogger.Info(args ...interface{})` is `fmt.Sprint`-style and just
concatenates everything into one string. The structured key/value variant is
`Infow(msg, keysAndValues ...interface{})`. Same bug also existed at the
"state dump generated" success log and in `ensureOpNodeBinary()`.

### Bug 2 — output captured silently

```go
out, err := cmd.CombinedOutput()
if err != nil {
    return "", fmt.Errorf("forge L2Genesis failed: %w\n%s", err, out)
}
```

`CombinedOutput` blocks until the process exits and only surfaces output on
failure. Forge L2Genesis is a long-running step (30–60s+), so nothing made it
to the logger until the end — even on success, where the captured buffer was
discarded.

### Bug 3 — unnecessary `--rpc-url` forced a remote fork

```go
cmd := exec.CommandContext(ctx, "forge", "script",
    "scripts/L2Genesis.s.sol:L2Genesis",
    "--rpc-url", l1RPCURL,
)
```

`L2Genesis.s.sol` does **not** read L1 state: it only uses Forge cheatcodes
(`vm.etch`, `vm.chainId`, `vm.startPrank`, `vm.dumpState`) to build predeploys
and write `state-dump-<l2ChainID>.json`. Passing `--rpc-url` causes forge to
fork the remote chain for the script's EVM context, which adds a fork-setup
roundtrip to the L1 RPC for no computational benefit.

Evidence this is safe to drop:
- `grep -E "vm\.(rpc|createFork|selectFork|rollFork)|block\.(number|timestamp|chainid)"`
  over the script — no matches.
- Upstream's own canonical invocation in
  `tokamak-thanos/packages/tokamak/contracts-bedrock/package.json`:
  ```json
  "genesis": "forge script scripts/L2Genesis.s.sol:L2Genesis --sig 'runWithStateDump()'"
  ```
  — no `--rpc-url`.
- `run()` in the script is aliased to `runWithStateDump()`, so `--sig` is
  also unnecessary.

## Fix

In `trh-sdk/pkg/stacks/thanos/genesis_prep.go`:

| Before | After |
|--------|-------|
| `logger.Info(msg, k, v, …)` | `logger.Infow(msg, k, v, …)` |
| `forge … --rpc-url <L1>` | `forge …` (no `--rpc-url`) |
| `cmd.CombinedOutput()` | `cmd.StdoutPipe`/`StderrPipe` + line scanner per stream, each line logged with `[forge]` prefix |

Also updated `deploy_contracts.go` call site to drop the now-unused
`l1RPCURL` argument.

Streaming uses a direct `bufio.Scanner` on the pipes (not
`utils.ExecuteCommandStreamInDir`) because that helper does not pass custom
env vars, and the forge call needs `CONTRACT_ADDRESSES_PATH` /
`DEPLOY_CONFIG_PATH` set on the child process.

## Known Tradeoff — Pipe vs PTY Buffering

The streaming implementation uses plain stdout/stderr pipes, not a PTY.
Forge (Rust binary) checks `isatty(stdout)` and may switch to block-buffered
output when the descriptor is a pipe, in which case progress lines still
arrive as one batch near the end of the run. Functionally better than
`CombinedOutput` (output reaches the logger, and the `--rpc-url` speedup
lands regardless), but not guaranteed to be line-by-line progressive.

If the batched behavior is still a pain point, upgrade
`utils.ExecuteCommandStreamInDir` (which already uses PTY via `creack/pty`)
to take env vars, and switch this call to the PTY path. Not done here to
keep the surface area small.

## Verification

- `go build ./pkg/stacks/thanos/...` — pass
- `go vet ./pkg/stacks/thanos/...` — clean
- Existing unit tests in `pkg/stacks/thanos` — pass
- Runtime validation (local L2 deploy) — pending next deploy

## Related

- [[tokamak-deployer-logging]] — the preceding step; logs before
  `✅ All contracts deployed successfully!`
- [[thanos-deployer-analysis]] — Phase 5 (L2 Genesis generation) overview
- [[l2-deploy-local]] — full local deployment walkthrough
