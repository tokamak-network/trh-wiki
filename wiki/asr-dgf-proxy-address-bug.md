---
title: ASR/DGF Proxy Address Bug — AnchorStateRegistry initialized with implementation address
date: 2026-05-05
status: fixed
tags: [fault-proof, tokamak-deployer, bugfix]
---

# ASR/DGF Proxy Address Bug

## Symptom

After fault proof deployment, `FaultDisputeGame.resolve()` always reverts.
`resolveClaim(0, 512)` succeeds (game clock expired, subgame resolved) but
`resolve()` fails with custom error `0x6b0f6891` = `UnregisteredGame()`.
Game status stays `IN_PROGRESS` indefinitely.

## Root Cause

`contracts.go` step 31 deploys the AnchorStateRegistry implementation and
passes the DGF **implementation** address to the constructor instead of the
DGF **proxy** address:

```go
// WRONG (before fix)
anchorStateRegistryImplAddr, err := deployContract(
    ctx, client, auth, &nonce, gasPrice,
    anchorStateRegistryArtifact,
    disputeGameFactoryImplAddr,   // ← implementation, not proxy!
)

// CORRECT (after fix)
anchorStateRegistryImplAddr, err := deployContract(
    ctx, client, auth, &nonce, gasPrice,
    anchorStateRegistryArtifact,
    disputeGameFactoryProxyAddr,  // ← proxy
)
```

The AnchorStateRegistry stores the DGF address as an **immutable** set in the
constructor. All game state lives in the proxy's storage (delegatecall). When
`tryUpdateAnchorState()` calls `DISPUTE_GAME_FACTORY.games()` on the
implementation address, it has no state → returns `address(0)` → `UnregisteredGame()`.

## Error Chain

```
FaultDisputeGame.resolve()
  └─ ANCHOR_STATE_REGISTRY.tryUpdateAnchorState()   // "should not revert"
       └─ DISPUTE_GAME_FACTORY.games(...)            // called on impl, not proxy
            └─ returns address(0)
                 └─ revert UnregisteredGame()         // 0x6b0f6891
```

## Fix

`tokamak-thanos/cmd/tokamak-deployer/internal/deployer/contracts.go` line 572:

Changed `disputeGameFactoryImplAddr` → `disputeGameFactoryProxyAddr`.

Commit: `11435dd788` in `tokamak-thanos`

## Verification

Stacks deployed before this fix have a permanently broken ASR — `resolve()` will
always revert on those stacks. New stacks deployed with `v0.0.8+` will have the
correct proxy address and games will resolve normally.

EFP-09 (`game resolves DEFENDER_WINS, AnchorStateRegistry anchors updated`)
requires a stack deployed after this fix to pass end-to-end.
