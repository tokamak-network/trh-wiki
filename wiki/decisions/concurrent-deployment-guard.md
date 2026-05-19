---

updated: 2026-05-19
sources: []
related: []
tags: [decision]
---
# Concurrent Deployment Guard — L1 Nonce Conflict Prevention

## Problem

The same seed phrase → same admin Ethereum address → concurrent Testnet/Mainnet deployments using the same key → **L1 nonce conflicts**. Two transactions submitted simultaneously with the same nonce cause one to fail.

Pre-existing guard `checkNoActiveLocalStack()` only blocked **Local+Local** deployments (Docker port conflicts). It did not block:
- Local+AWS concurrent deployments (both using Sepolia with same admin key)
- AWS+AWS concurrent deployments

## Solution

### Phase 1 — UI Guard (`trh-platform-ui`)

`src/app/rollup/create/page.tsx`:

```typescript
const isDeploymentInProgress = stacks.some(
  (s) =>
    (s.status === ThanosStackStatus.PENDING || s.status === ThanosStackStatus.DEPLOYING) &&
    s.network !== "LocalDevnet"
);
```

- Warning banner shown at step 3 when `isDeploymentInProgress`
- "Deploy Rollup" button replaced with tooltip+disabled span

**LocalDevnet exemption**: LocalDevnet uses an isolated local L1 node — no shared admin key with Testnet/Mainnet.

### Phase 2 — Backend Guard (`trh-backend`)

`pkg/services/thanos/stack_lifecycle.go`:

New `deployingStatuses` map:
```go
var deployingStatuses = map[entities.StackStatus]bool{
    entities.StackStatusPending:   true,
    entities.StackStatusDeploying: true,
}
```

New `checkNoActiveDeployingStack()` function:
- Queries all stacks via `s.stackRepo.GetAllStacks()`
- Skips stacks with status not in `deployingStatuses`
- Skips `LocalDevnet` network (isolated L1)
- For local-infra stacks with a `DeploymentPath`: reconciles with Docker reality to avoid stale-state false positives
- Returns `HTTP 409 Conflict` if any active non-LocalDevnet deployment found
- **Fail open**: DB query failure → allow deployment (log warn)

Called in `CreateThanosStack` after existing local stack check:
```go
if conflict := s.checkNoActiveDeployingStack(); conflict != nil {
    return conflict, nil
}
```

## Test Coverage

`pkg/services/thanos/check_deploying_stack_test.go` — 13 tests:
- No stacks → allowed
- Testnet+Pending → blocked (HTTP 409)
- Testnet+Deploying → blocked
- Mainnet+Deploying → blocked
- Local infra+Testnet+Deploying → blocked (empty DeploymentPath to skip Docker reconcile)
- LocalDevnet+Deploying → allowed (isolated L1)
- Deployed status → allowed (L1 contracts done)
- Terminated/Stopped/FailedToDeploy/FailedToTerminate → allowed
- AWS Deploying blocks new Local deploy → blocked (core regression)
- AWS Deploying blocks new AWS deploy → blocked
- DB error → allowed (fail open)

## Why LocalDevnet Is Exempt

`DeploymentNetworkLocalDevnet = "LocalDevnet"` spins up its own L1 Hardhat/Anvil node. Its deployer key is derived from the same seed phrase but operates on a completely isolated chain — there is no nonce overlap with Sepolia (Testnet) or Ethereum Mainnet.

## Docker Reconciliation Detail

For local-infra stacks (InfraProvider = "local") with a non-empty `DeploymentPath`:
- `hasRunningContainersForProject(projectName)` checks if Docker containers are actually running
- If containers are gone but DB status is still Deploying, the stack is auto-corrected to Terminated
- This prevents a stale zombie stack from permanently blocking new deployments after a crash

## Commits

- `trh-backend` — `fdb772d`: `feat(thanos): block concurrent deployments to prevent L1 nonce conflicts`
- `trh-platform-ui` — `3e23bfe`: `feat(ui): disable deploy button when another deployment is in progress`
