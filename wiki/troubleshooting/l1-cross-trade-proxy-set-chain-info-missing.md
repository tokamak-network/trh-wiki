---

updated: 2026-05-19
sources: []
related: []
tags: [troubleshooting]
---
# L1CrossTradeProxy.setChainInfo Missing in AWS Auto-Install

## Symptoms

- `provideCT` on `L1CrossTradeProxy` always reverts
- `L1CrossTradeProxy.chainData(l2ChainId)` returns `(address(0), address(0))` after CrossTrade deployment
- E2E test EFR-07: `l1_registration_tx_hash missing in integration info`

## Root Cause

`AutoInstallCrossTradeAWS` deploys L2 contracts via `DeployCrossTradeLocal` (which sets the L2-side
chain info on `L2CrossTradeProxy`) but never calls `L1CrossTradeProxy.setChainInfo()` to register
the L2 chain on the L1-side shared contract.

The manual installation path (`trh install cross-trade`) does this via the Foundry script
`SetChainInfoL1_L2L1.sol`, but the AWS auto-install path had no equivalent.

Without `setChainInfo`, `L1CrossTradeProxy.chainData(l2ChainId)` returns zeros, so the contract
cannot route `provideCT` transactions to the correct L2 chain.

## setChainInfo Signature

```solidity
// L1CrossTradeProxy (shared Sepolia contract: 0xf3473E20F1d9EB4468C72454a27aA1C65B67AB35)
function setChainInfo(
    address _crossDomainMessenger,
    address _l2CrossTrade,
    uint256 _l2chainId
) external
```

Parameters:
- `_crossDomainMessenger` → `L1CrossDomainMessengerProxy` (from stack deploy-output)
- `_l2CrossTrade` → `L2CrossTradeProxy` (from `DeployCrossTradeLocal` output)
- `_l2chainId` → L2 chain ID

## chainData Return Values

```solidity
function chainData(uint256) external view returns (
    address crossDomainMessenger,
    address l2CrossTradeContract
)
```

Note: only **2** return values (not 3). Earlier E2E test ABI mistakenly declared a 3rd `nativeToken`
field, causing ethers v6 `BAD_DATA` decode error on 64-byte (2-slot) return data.

## Fix

`trh-sdk/pkg/stacks/thanos/deploy_chain.go` → added `setL1CrossTradeChainInfo()` function.
`trh-sdk/pkg/stacks/thanos/cross_trade_aws.go` → `AutoInstallCrossTradeAWS()` calls it after
`DeployCrossTradeLocal` succeeds.

Idempotency: reads `chainData(l2ChainId)` first; skips if `crossDomainMessenger` is already non-zero.
