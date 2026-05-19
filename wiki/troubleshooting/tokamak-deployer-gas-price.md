---
updated: 2026-04-17
category: decision
sources: []
related:
  - "[[tokamak-deployer-logging]]"
  - "[[l2-deployment]]"
  - "[[thanos-deployer-analysis]]"
  - "[[trh-sdk]]"
tags: [troubleshooting]
---


# tokamak-deployer Fixed Gas Price Strategy (v0.0.5+)

## Problem before v0.0.5

Each of the 26-32 L1 deployment transactions called `SuggestGasPrice` individually:

```go
// contracts.go (v0.0.4 and prior)
func deployRawContract(...) {
    gasPrice, err := client.SuggestGasPrice(ctx)  // ← per-TX round-trip
    ...
}
```

Consequences:
- **25-31 extra RPC round-trips** per deploy (~10s of pure network overhead on remote RPCs)
- **Price drift across TXs** — two TXs in the same deploy could race the mempool at slightly different prices, letting the later one jump ahead
- **Bump-on-timeout retry loop fired often** — the initial suggested price was barely above mempool's minimum, so even small block-time variance caused the 90s timeout to expire, bumping gas 1.25× and replacing the TX (burning budget on the replaced one)

Before the change, a healthy Sepolia deploy took ~10-15 minutes with occasional 2-3 minute stalls when a TX sat at the suggested price and got priced out.

## Design decision (v0.0.5)

Resolve the gas price **once** at `Deploy()` startup and reuse it for every subsequent TX. Mirrors Foundry's `forge script --with-gas-price` pattern from the legacy deploy path (see `ops-bedrock/scripts/sepolia-oneclick.sh:253` in tokamak-thanos).

```
                           ┌────────────────────────────────┐
trh-sdk                    │  resolveGasPrice (once)         │
  SuggestGasPrice × 2  ──► │    → clamped to [floor, ceil]   │ ──► applied to all 26-32 TXs
  via --gas-price flag     └────────────────────────────────┘
```

### Parameters and defaults

| Knob | Default | Env / CLI | Why |
|---|---|---|---|
| `GasPriceMultiplier` | 200 (= 2×) | `--gas-price-multiplier` | Covers Sepolia price doubling during a 10-min deploy |
| `GasPriceFloor` | 1 Gwei | `--gas-price-floor` | Guards against the historical "gasPrice=0" RPC/big-int bug (v0.0.1) |
| `GasPriceCeil` | 100 Gwei | `--gas-price-ceil` | Caps mainnet congestion cost |
| `FixedGasPrice` | — (auto) | `--gas-price` or `TOKAMAK_DEPLOY_GAS_PRICE` | Explicit override; bypasses multiplier, still clamped |
| `sendMaxAttempts` | 3 (was 5) | constant | Safety net only — should almost never fire |
| `sendAttemptTimeout` | 180s (was 90s) | constant | Absorbs Sepolia block-time variance without replacing TXs |

### Why a `user-specified` vs `suggested × 200%` log matters

At startup, `resolveGasPrice` logs either:
```
[deployer] Fixed gas price: <wei> (<Gwei>) — user-specified
```
or
```
[deployer] Fixed gas price: <wei> (<Gwei>) — suggested <wei> × 200%
```

The suffix tells you whether the caller (trh-sdk) passed `--gas-price` or let the deployer auto-compute. trh-sdk sets the suffix to `user-specified` on the fresh-deploy path and leaves it `suggested × ...` on the resume path (see `pkg/stacks/thanos/deploy_contracts.go` hoist of `gasPriceWei` is only on fresh deploy).

## Measured results — Sepolia, 2026-04-17

Run on `0x7220c734653ae8Ca014d4D82A84041EE4169499c`, L1 chain 11155111, `tokamak-deployer/v0.0.5`:

| Metric | Value |
|---|---|
| Total wall-clock | **5m47s** (347s) |
| Steps completed | 26 / 26 ✅ |
| Retry / bump fired | **0 times** ✅ |
| Fixed gas price held throughout | **1 Gwei** (suggested was 0.031 Gwei; floor clamped to 1 Gwei) |
| Per-step avg | 13.3s (min 10s, max 26s, median 12s) |
| Deploy cost | 0.0196 ETH |
| Nonces consumed | 1839 → 1864 (26 TXs) |

Outliers at 23s / 26s are block-time variance (one block occasionally takes >20s on Sepolia). Even these stayed well under the 180s per-attempt timeout, so the bump-retry path never engaged.

### Before / After summary

| Dimension | v0.0.4 (pre-change) | v0.0.5 (measured) |
|---|---|---|
| `eth_gasPrice` RPC round-trips | 26-32 (per TX) | **1** (startup) |
| Per-TX gas price variance | Varied with RPC | Constant |
| Timeout/bump frequency | Gas-price-sensitive | 0 (measured) |
| Sepolia wall-clock (low-congestion) | ~10-15 min (reported) | **5m47s** |

## When the floor kicks in

When Sepolia suggested price is very low (< 0.5 Gwei), trh-sdk's `gasPriceWei × 2` still falls below the 1 Gwei floor, so the effective price is the floor. This is the common case on quiet Sepolia — and it's why the deployer observed `1 Gwei — user-specified` above. The floor is deliberately higher than the suggested price to ensure TXs clear the mempool promptly even if it drifts upward.

## Risks and escape hatches

| Risk | Mitigation |
|---|---|
| Sudden Sepolia price spike > 2× during deploy | `sendAndWaitMined` retry loop is still present as a safety net (3 attempts × 1.25× bump each) |
| Mainnet congestion over 100 Gwei | Ceil clamps the price; deploy fails fast with stuck-TX error rather than bleeding budget |
| RPC returns 0 / 1 wei | Floor of 1 Gwei makes the deploy go through at 1 Gwei regardless |
| Caller needs an exact price | `--gas-price <wei>` or `TOKAMAK_DEPLOY_GAS_PRICE=<wei>` forces the value (still clamped by floor/ceil; raise ceil if needed) |

## Related

- [[tokamak-deployer-logging]] — Log format reference, debugging workflow
- [[l2-deployment]] — Where this fits in the overall L2 deploy pipeline
- [[thanos-deployer-analysis]] — Deeper architecture analysis
- [[trh-sdk]] — Caller side: `pkg/stacks/thanos/deploy_contracts.go` computes `gasPriceWei × 2`, `deployer_binary.go` threads it through `--gas-price`
