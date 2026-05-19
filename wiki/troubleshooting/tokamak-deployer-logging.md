---
updated: 2026-04-17
category: troubleshooting
sources: []
related:
  - "[[tokamak-deployer-gas-price]]"
  - "[[l2-deployment]]"
  - "[[sequential-l2-deploy]]"
  - "[[trh-sdk]]"
tags: [troubleshooting]
---


# tokamak-deployer Logging & Observability

## Problem

tokamak-deployer v1.0.0 had zero logging, making it impossible to diagnose deployment hangs. When a deployment stopped unexpectedly, there was no way to determine:
- Which of the 32 contract deployment steps was executing
- Whether transactions were being broadcast to the L1 RPC
- Where in the pipeline the process got stuck

This led to silent failures requiring manual investigation and log analysis.

## Solution (v1.0.1+)

**Comprehensive two-level logging added**:

### High-Level Progress Logging

At the start of `Deploy()`:
```
[deployer] Starting contract deployment for L2 chain XXXX
[deployer] Connected to L1 RPC
[deployer] L1 chain ID: 11155111 (or 1 for mainnet)
[deployer] Starting nonce: N, deployer address: 0x...
[deployer] Fixed gas price: <wei> (<Gwei>) — suggested <wei> × 200%   # v0.0.5+
```

For each contract deployment:
```
[deployer] Step X/26: Deploying ContractName
[deployer] ✓ ContractName deployed: 0xAddress
```

Final status:
```
[deployer] ✅ All contracts deployed successfully!
```

### Low-Level Transaction Logging

In `sendAndWaitMined()` for each transaction (v0.0.5+):
```
[deployer] deploy(nonce=N, X bytes): broadcasting (attempt 1/3, hash: 0xHash)
[deployer] Transaction mined in block XXXXXX (status: 1)
[deployer] Contract deployed at: 0xAddress
```

For contract method calls (proxy upgrades):
```
[deployer] call upgrade(nonce=N): broadcasting (attempt 1/3, hash: 0xHash)
[deployer] ✓ ContractProxy upgraded
```

**Retry / bump logs** (rare — fires only if a TX is not mined in 180s):
```
[deployer] <label>: tx 0xHash not mined within 3m0s, will retry with bumped gas
[deployer] <label>: attempt 2 bumping gas price to <wei>
```

## Debugging Workflow

When deployment hangs:

1. **Check last log message** → identifies the step (e.g., "Step 15/26")
2. **If stuck on broadcasting** → transaction hash is logged, can verify on L1 explorer
3. **If stuck on mining** → check L1 RPC status, gas prices, balance
4. **If `attempt 2` / `attempt 3` appears** → initial gas price was priced out of the mempool, consider raising `--gas-price-multiplier` or setting `--gas-price` manually
5. **If no log output** → deployment never started (setup/connection issue)

## Technical Details

- **Logging API**: Go standard `log.Printf()`
- **Output**: Flows to stdout/stderr → captured in parent process (Docker logs or trh-sdk log stream)
- **Format prefix**: `[deployer]` — easily filterable in Docker logs

## Version History

| Version | Change |
|---------|--------|
| v1.0.0  | Initial release, zero logging |
| v1.0.1  | Added 50+ logging statements for step-by-step visibility |
| v0.0.1  | Renamed versioning scheme (monorepo tag `tokamak-deployer/v0.0.x`); fixed `gasPrice.Div` in-place bug |
| v0.0.2  | Added gas-bump retry safety net (5 attempts × 90s timeout) |
| v0.0.3–v0.0.4 | op-node integration for `generate-genesis`, minor refactors |
| v0.0.5  | **Per-TX `SuggestGasPrice` removed**; one-shot fixed gas price at startup + reuse for all 26-32 TXs; retry tuned to 3×180s. See [[tokamak-deployer-gas-price]]. |

## Related

- [[tokamak-deployer-gas-price]] — Fixed gas price strategy (v0.0.5+) with measured Sepolia results
- [[l2-deployment]] — Full deployment flow, where tokamak-deployer is invoked
- [[sequential-l2-deploy]] — Why deployments must be sequential
- [[trh-sdk]] — Where deployer version is pinned (pkg/stacks/thanos/deployer_binary.go)
