---
title: thanos-deployer Deployment Logic Analysis
date: 2026-04-16
status: final
tags: [deployment, L1, L2, genesis, preset]
---

# thanos-deployer Deployment Logic Analysis

## Overview

Complete code-level analysis of the thanos-deployer deployment pipeline: from Electron UI deployment request through L1 contract deployment (Foundry), L2 Genesis generation (op-chain-ops), to result persistence and client notification.

**Scope**: Electron → trh-backend → trh-sdk → Foundry → op-chain-ops → StackMetadata → Client

**Not Covered**: AWS infrastructure, Solidity implementation, local Docker deployment details

## Key Findings

### System Architecture (8 Layers)

1. **Electron Client** — Web UI + AWS SSO authentication
2. **trh-platform** — OAuth token management + deployment orchestration
3. **trh-backend** — HTTP API, task queueing via TaskManager
4. **trh-sdk** — L1 deployment orchestration + infrastructure provisioning
5. **Foundry Scripts** — Smart contract deployment (35+ contracts)
6. **op-chain-ops Deployer** — L2 genesis creation (14+ steps, 40+ predeploys)
7. **Database** — StackMetadata persistence
8. **Client Notification** — Result delivery to web UI

### Deployment Flow (6 Phases)

- **Phase 1**: Electron SSO authentication (prerequisite)
- **Phase 2**: Web UI deployment request → HTTP POST /api/v1/stacks/thanos
- **Phase 3**: Backend queuing and async task orchestration via TaskManager
- **Phase 4**: L1 contract deployment via Foundry (35+ contracts, 4 sequential phases, conditional FaultProof/Plasma)
- **Phase 5**: L2 Genesis generation via op-chain-ops (14+ steps, 40+ predeploys, bytecode patching)
- **Phase 6**: Result persistence, status updates, client notification

### Critical Findings

**Call Depth**: 8+ synchronous function calls from HTTP handler to op-chain-ops entry point

**Data Transformations**: DeployThanosRequest JSON → .env → deploy.json → op-chain-ops → genesis.json (3 intermediate serialization steps)

**State Mutations**: 6 major data structure transformations, 14 predeploy bytecode patch operations

**Known Pitfalls**:
1. Blob fee spike handling (excessBlobGas edge case) — See [[op-batcher-blob-fee-spike]]
2. Environment variable substitution validation (missing .env checks → zero addresses)
3. Cross-Trade scope flag isolation (local-only deployment vs L2-L2 cross-chain)
4. Immutable injection bytecode offset hardcoding (Openzeppelin upgrades shift offsets)
5. Hard fork version compatibility (Ecotone/Fjord/Granite protocol mismatch)

## Complete Documentation

### Main Analysis Document

📄 **[thanos-deployer-flow-analysis.md](../../tokamak-thanos/docs/analysis/thanos-deployer-flow-analysis.md)** (1,368 lines)

- 6 Phase sections with code-level details
- Appendix A: Unified call graph
- Appendix B: Data structures & transformations
- Appendix C: Known pitfalls & improvements
- Appendix D: Verification checklist
- Appendix E: Diagram reference & index
- Appendix F: Related wiki & documentation

### Phase-Specific Analyses

- 📋 **PHASE_2_ANALYSIS.md** — Web UI request handling
- 📋 **PHASE_3_ANALYSIS.md** — Backend queuing & orchestration
- 📋 **PHASE_4_ANALYSIS.md** — L1 contract deployment (Foundry)
- 📋 **PHASE_5_ANALYSIS.md** — L2 Genesis generation (op-chain-ops)
- 📋 **PHASE_6_ANALYSIS.md** — Result persistence & notification

### Code Reference

- 📊 **code-reference-table.md** — 51 functions mapped across 45 files
  - 6 phase-specific tables
  - Cross-phase call chain (20+ rows)
  - Data structure mapping

## Key Code References

### Entry Point

**HTTP Handler**: `trh-backend/pkg/api/handlers/thanos/deployment.go:32`

- Function: `Deploy(c *gin.Context)`
- Reads: DeployThanosRequest JSON
- Calls: `CreateThanosStack()` → enqueues to TaskManager
- Returns: 202 Accepted with stackId

### Backend Task Orchestration

**Task Manager**: `trh-backend/pkg/services/thanos/task_manager.go`

- Function: `ExecuteDeploymentTask(stackId string)`
- Calls: `DeployContracts()` → `DeployL2Genesis()` → `UpdateStackMetadata()`
- State Machine: Queued → InProgress → Deployed/Failed → Persisted
- Timeout: Configurable (default 30min)

### L1 Deployment

**SDK Orchestration**: `trh-sdk/pkg/stacks/thanos/deploy_contracts.go:33`

- Function: `DeployContracts(ctx context.Context, input *DeployContractsInput) error`
- Calls: `start-deploy.sh` (shell-out to Foundry)
- Input: L1RpcUrl, deployer private key, preset config
- Output: `deploy.json` with contract addresses
- 4 Phases: Core System → Token System → L2OutputOracle → FaultProof/Plasma (conditional)

### L2 Genesis

**op-chain-ops Entry**: `op-chain-ops/deployer/deployer.go`

- Function: `NewL2Genesis(...) (*core.Genesis, error)`
- Input: L1DeployOutput (deploy.json)
- Output: genesis.json + rollup.json
- 14+ step process with predeploy immutable patching
- Handles: Bytecode injection, state root computation, hardfork config

### Result Persistence

**Metadata Update**: `trh-backend/pkg/services/thanos/stack_lifecycle.go:280`

- Function: `UpdateStackMetadata(stackId, metadata)`
- Persists: StackMetadata to database
- Triggers: Client notification webhook
- Status: Deployed / Failed
- Records: ContractAddresses, GenesisPath, DeploymentLogs

## Risk Analysis

### High Risk

- **Bytecode patching**: Hardcoded byte offsets per contract version
  - Risk: Openzeppelin upgrades → offset shift → immutable injection fails
  - Mitigation: Validate offset ranges before patching
  
- **Environment validation**: Missing .env variable checks
  - Risk: Contract addresses may be zero → deployment succeeds but invalid
  - Mitigation: Pre-deployment validation of all contract addresses
  
- **Hard fork mismatch**: Genesis config doesn't match L1 fork version
  - Risk: Protocol incompatibility → chain rejections
  - Mitigation: Cross-check hardfork versions in deploy.json vs genesis.json

### Medium Risk

- **Large genesis files**: 20-100MB files with slow I/O
  - Risk: Timeout on slow storage
  - Mitigation: Implement streaming JSON generation
  
- **Context cancellation**: Partial state cleanup when deployment interrupted
  - Risk: Orphaned contracts or incomplete genesis state
  - Mitigation: Idempotent re-entry logic
  
- **Create2 determinism**: Assuming specific bytecode versioning
  - Risk: Compiler version changes → Create2 addresses shift
  - Mitigation: Pin foundry version in trh-sdk

### Low Risk

- **Preset parsing**: YAML/JSON parsing errors
  - Mitigation: Validation schemas (zod / protobuf)
  
- **ReuseDeployment flag**: Safety not fully verified
  - Mitigation: Add idempotency check in deploy.json comparison

## Verification Checklist

```bash
# Verify Phase analyses match current code
grep -r "DeployContracts\|DeployL2Genesis\|UpdateStackMetadata" \
  /Users/theo/workspace_tokamak/tokamak-thanos \
  /Users/theo/workspace_tokamak/trh-sdk \
  /Users/theo/workspace_tokamak/trh-backend

# Verify op-chain-ops deployer entry point
grep -n "NewL2Genesis" /Users/theo/workspace_tokamak/tokamak-thanos/op-chain-ops/deployer/deployer.go | head -5

# Verify contract count (35+ for Thanos)
grep -c "forge script" /Users/theo/workspace_tokamak/tokamak-thanos/packages/contracts-bedrock/scripts/Deploy.s.sol

# Verify predeploy count (40+ for op-chain-ops)
grep -c "PredeploySystemContracts\|setupPredeploy" \
  /Users/theo/workspace_tokamak/tokamak-thanos/op-chain-ops/deployer/deployer.go

# Verify bytecode patch operations
grep -c "bytecode\|offset" \
  /Users/theo/workspace_tokamak/tokamak-thanos/docs/analysis/PHASE_5_ANALYSIS.md

# Check blob fee spike mitigation
git log --oneline --grep="blob" /Users/theo/workspace_tokamak/tokamak-thanos | head -5
```

## Related Documentation

- **[[ec2-deploy]]** — AWS EC2 deployment procedures (Terraform+Helm)
- **[[tokamak-thanos-stack]]** — Infrastructure (Terraform/Helm IaC)
- **[[troubleshooting]]** — Known issues and fixes
- **[[design-decisions]]** — Architecture rationale
- **[[preset-system]]** — Preset configuration system
- **[[op-batcher-blob-fee-spike]]** — Blob fee handling workarounds

## Tools & Integration

### For Developers

- Use **code-reference-table.md** to find function locations
- Use **call-graph** (Appendix A) to understand function dependencies
- Use **data-flow** diagram to track data transformations
- Use **pitfalls** (Appendix C) to identify edge cases

### For DevOps

- Use **phase descriptions** to understand deployment stages
- Use **pitfalls** (Appendix C) to identify risk areas
- Use **verification checklist** (Appendix D) to validate changes
- Monitor: L1 RPC rate limits, Foundry script timeouts, op-chain-ops memory usage

### For Architects

- Use **system-architecture** diagram for module boundaries
- Use **data structures** (Appendix B) for schema design
- Use **pitfalls & improvements** (Appendix C) for roadmap items
- Review: Create2 determinism, idempotency, context cancellation handling

## Last Updated

2026-04-16 by Claude Code (via subagent-driven-development)

**Previous commits**:
- tokamak-thanos: d8202223de, 8e67bbce7f, 2a9e294c32 (blob fee fixes)
- trh-wiki: See log.md [2026-04-15] entries
