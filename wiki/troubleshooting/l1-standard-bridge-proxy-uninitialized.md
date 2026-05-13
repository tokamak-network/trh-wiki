# L1StandardBridgeProxy Uninitialized

## Symptoms

- `bridgeETH()` or `bridgeERC20()` calls always revert (on-chain receipt status=0)
- `messenger()` on `L1StandardBridgeProxy` returns `address(0)` after deployment
- Low gas used on revert (~63,000) — fails inside the messenger null-check, not running actual bridge logic
- `MESSENGER()` (uppercase alias) also returns zero

## Root Cause

`tokamak-deployer` calls `upgrade(proxy, impl)` to set the implementation but never calls
`initialize(CrossDomainMessenger, SuperchainConfig, SystemConfig)` on `L1StandardBridgeProxy`.
The proxy's initializer is never run, so all storage slots (messenger, superchainConfig, systemConfig,
otherBridge) remain at their zero values.

This is the same pattern as [`OptimismPortalProxy uninitialized`](./optimism-portal-proxy-uninitialized.md)
and [`L2OutputOracle uninitialized`](./l2-output-oracle-uninitialized.md).

## Initialize Signature

```solidity
// L1StandardBridge.sol (tokamak-thanos fork)
function initialize(
    CrossDomainMessenger _messenger,
    SuperchainConfig _superchainConfig,
    SystemConfig _systemConfig
) public initializer
```

Parameters to pass:
- `_messenger` → `L1CrossDomainMessengerProxy`
- `_superchainConfig` → `SuperchainConfigProxy`
- `_systemConfig` → `SystemConfigProxy`

## Fix

`trh-sdk/pkg/stacks/thanos/deploy_chain.go` → `deployNetworkToAWS()` init goroutine.

Added `initL1StandardBridge()` call immediately after `initL1CrossDomainMessenger()`.
The function follows the same idempotency-guard pattern: reads `messenger()` and skips if non-zero.

Commit: added in same session as `setL1CrossTradeChainInfo` fix.

## Detection

```typescript
// In E2E test (EFR-06):
const messengerAddr = await bridgeCheck.messenger();
bridgeInitialized = messengerAddr !== ethers.ZeroAddress;
```

If `bridgeInitialized` is false, `bridgeETH` will always revert.
