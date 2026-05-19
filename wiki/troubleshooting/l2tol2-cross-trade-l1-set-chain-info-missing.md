---

updated: 2026-05-19
sources: []
related:
  - "[[l1-cross-trade-proxy-set-chain-info-missing]]"
tags: [troubleshooting]
---
# L2toL2CrossTradeL1.setChainInfo Missing in AWS Auto-Install

## Symptoms

- L2→L2 bridge requests revert on the dApp
- `L2toL2CrossTradeL1.chainData(l2ChainId)` returns zero addresses after CrossTrade deployment
- L2→L1 bridging works fine; only L2→L2 direction fails
- Confirmed via deployment log: no `L2toL2CrossTradeL1.setChainInfo` entry between
  `"✅ L1CrossTradeProxy chain info registered"` and ALB ingress poll

## Root Cause

`AutoInstallCrossTradeAWS` in `trh-sdk` called only `setL1CrossTradeChainInfo` (covering L2→L1
direction via `L1CrossTradeProxy`) but never called the equivalent registration for L2→L2 direction
on `L2toL2CrossTradeL1`.

The local path uses `RegisterCrossTradeL2` in `trh-backend` which handles both directions (3-param
and 7-param setChainInfo). The AWS auto-install path had no equivalent for the L2→L2 L1 registration.

Without this call, `L2toL2CrossTradeL1.chainData(l2ChainId)` returns zeros, so any L2→L2 bridge
request reverts at the L1 contract level.

## setChainInfo Signature (7-param)

```solidity
// L2toL2CrossTradeL1 (shared Sepolia contract: 0xd038d89655f106d88c5bd56a9442d9ecee675c1c)
function setChainInfo(
    address _crossDomainMessenger,
    address _l2CrossTrade,
    address _l2NativeTokenAddressOnL1,
    address _l1StandardBridge,
    address _l1USDCBridge,
    uint256 _l2ChainId,
    bool _useCustomBridge
) external
```

Parameters for AWS auto-install:
- `_crossDomainMessenger` → `L1CrossDomainMessengerProxy` (from stack deploy-output)
- `_l2CrossTrade` → `L2toL2CrossTradeProxy` (from `DeployCrossTradeLocal` output)
- `_l2NativeTokenAddressOnL1` → TON address on L1 (`L1ChainConfigurations[l1ChainID].TON`)
- `_l1StandardBridge` → `L1StandardBridgeProxy` (from stack deploy-output)
- `_l1USDCBridge` → `address(0)` (no USDC bridge in AWS auto-install)
- `_l2ChainId` → L2 chain ID
- `_useCustomBridge` → `false`

Contrast with 3-param L1CrossTradeProxy.setChainInfo — see [[l1-cross-trade-proxy-set-chain-info-missing]].

## Fix

`trh-sdk` commit `8aba331`:
- `deploy_chain.go` → added `setL2toL2CrossTradeL1ChainInfo()` function with idempotency guard
- `cross_trade_aws.go` → `AutoInstallCrossTradeAWS()` calls it after `setL1CrossTradeChainInfo`

Idempotency: reads `chainData(l2ChainId)` first; skips if `crossDomainMessenger` is already non-zero.
