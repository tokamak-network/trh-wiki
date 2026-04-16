---
updated: 2026-04-16
category: troubleshooting
---

# tokamak-deployer Logging & Observability

## Problem

tokamak-deployer v1.0.0 had zero logging, making it impossible to diagnose deployment hangs. When a deployment stopped unexpectedly, there was no way to determine:
- Which of the 32 contract deployment steps was executing
- Whether transactions were being broadcast to the L1 RPC
- Where in the pipeline the process got stuck

This led to silent failures requiring manual investigation and log analysis.

## Solution (v1.0.1)

**Comprehensive two-level logging added**:

### High-Level Progress Logging

At the start of `Deploy()`:
```
[deployer] Starting contract deployment for L2 chain XXXX
[deployer] Connected to L1 RPC
[deployer] L1 chain ID: 1 (or sepolia)
[deployer] Starting nonce: N, deployer address: 0x...
```

For each contract deployment:
```
[deployer] Step X/32: Deploying ContractName
[deployer] ✓ ContractName deployed: 0xAddress
```

Final status:
```
[deployer] ✅ All contracts deployed successfully!
```

### Low-Level Transaction Logging

In `deployRawContract()` for each transaction:
```
[deployer] Suggested gas price: XXX Gwei
[deployer] Broadcasting transaction: 0xHash (nonce: N, gas: XXXX bytes)
[deployer] Transaction sent: 0xHash
[deployer] Waiting for transaction to be mined...
[deployer] Transaction mined in block XXXXXX (status: 1)
[deployer] Contract deployed at: 0xAddress
```

## Debugging Workflow

When deployment hangs:

1. **Check last log message** → identifies the step (e.g., "Step 15/32")
2. **If stuck on broadcasting** → transaction hash is logged, can verify on L1 explorer
3. **If stuck on mining** → check L1 RPC status, gas prices, balance
4. **If no log output** → deployment never started (setup/connection issue)

## Technical Details

- **Logging API**: Go standard `log.Printf()`
- **Output**: Flows to stdout/stderr → captured in parent process (Docker logs)
- **No performance cost**: Logging disabled in compiled output if `log` package not used (but here it is)
- **Format prefix**: `[deployer]` — easily filterable in Docker logs

## Version History

| Version | Change |
|---------|--------|
| v1.0.0  | Initial release, zero logging |
| v1.0.1  | Added 50+ logging statements for step-by-step visibility |

## Related

- [[l2-deployment]] — Full deployment flow, where tokamak-deployer is invoked
- [[sequential-l2-deploy]] — Why deployments must be sequential
- [[trh-sdk]] — Where deployer version is pinned (pkg/stacks/thanos/deployer_binary.go)
