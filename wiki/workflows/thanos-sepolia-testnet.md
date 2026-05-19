---
updated: 2026-05-19
sources:
  - raw/inbox/thanos-sepolia-information.md
related:
  - "[[tokamak-thanos]]"
  - "[[thanos-bridge]]"
  - "[[l2-deployment]]"
  - "[[l2-deploy-local]]"
tags: [workflow]
---

# Thanos Sepolia Testnet — Reference Deployment

Live Thanos L2 Testnet running on Ethereum Sepolia (L1 chain ID 11155111). Operated by Tokamak Network. Deployment UUID `8671124e-6972-42fb-92d2-42edf482a7fd`. Fault Proof enabled with Cannon proving system. L2OutputOracle is deployed but unused — the proposer submits to `DisputeGameFactory` instead.

---

## Endpoints

| Name | URL |
|------|-----|
| L2 RPC (http) | https://rpc.thanos-sepolia.tokamak.network |
| L2 RPC (ws) | wss://rpc.thanos-sepolia.tokamak.network |
| Explorer | https://explorer.thanos-sepolia.tokamak.network |
| Bridge | https://bridge.thanos-sepolia.tokamak.network |
| L1 Chain ID | 11155111 (Sepolia) |
| L2 Chain ID | 111551132354 |

All public endpoints route through Cloudflare Tunnel `00637630-de80-402f-8d58-09ad4c53882a` to `localhost:8080` via nginx.

---

## Accounts

Key manager: Theo

| Account | Address |
|---------|---------|
| Admin | `0x7220c734653ae8Ca014d4D82A84041EE4169499c` |
| P2PSequencer | `0x6B2DBEeA40782f9D3578926A3F1b8890F4897314` |
| Batcher | `0x79A7A04580F725b4e9AC77047BABEf755b763F95` |
| Proposer | `0x631cE643054fD257349E4FA084dbF4aDBc03A60C` |
| Challenger | `0x0bAc6f720d782d746EE8851713B4f1279dcd5160` |

---

## L1 Contracts (Sepolia)

All contracts from deployment UUID `8671124e-6972-42fb-92d2-42edf482a7fd` (deploy-output.json).

| Contract | Address |
|----------|---------|
| `OptimismPortalProxy` | `0xf6168f0caC94d88550bB09c7d55C170199eF1d47` |
| `L1CrossDomainMessengerProxy` | `0xD28D1C8d4017cFb7126Bf501E7C0fFf8aAB3B758` |
| `L1StandardBridgeProxy` | `0x52A0CCA2600c50B316e382fEb511D4274867B6f0` |
| `SystemConfigProxy` | `0xa22C9EecAE48E192D7280152b322e2681104a537` |
| `DisputeGameFactoryProxy` | `0xD894A89FdD8d40d3e4708b63f7d9524F3946EC9D` |
| `AnchorStateRegistryProxy` | `0x3eF37ae5Fdb5CbB4cc677CEc6dbecE0648D43439` |
| `DelayedWETHProxy` | `0x4ACb1A9BAff876c9a474866044B190725FBB56E3` |
| `L2OutputOracleProxy` | `0x458Fe10728c3E4aB6e0F89ac06D3c2793419aEd8` *(deployed but unused — fault proof mode)* |
| `L1ERC721BridgeProxy` | `0x47e547A05e01f997dc34763F3a50a055b6be1c6f` |
| `OptimismMintableERC20FactoryProxy` | `0x5048DB3521dbB3CC0487E7C68DB1FFBd2e0bE97E` |
| `ProxyAdmin` | `0xB7E4D2701D7FD5F4f403aEA0e82bCA2999882251` |
| `AddressManager` | `0x1595516d0F723e6896b300e9ebC8C6489F591abE` |
| `SuperchainConfigProxy` | `0xa517f38d26787569138493fe840156d6f9Aa445c` |
| `TON` | `0xa30fe40285B8f5c0457DbC3B7C8A280373c40044` |
| `USDC` | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| `USDT` | `0xaa8e23fb1079ea71e0a56f48a2aa51851d8433d0` |

---

## Fault Proof System

`useFaultProofs: true` — the proposer submits dispute games to `DisputeGameFactory` every 30 minutes. `L2OutputOracle` is present on-chain but ignored. See [[tokamak-thanos]] for the op-proposer/op-challenger architecture.

### Contracts

| Contract | Address |
|----------|---------|
| `DisputeGameFactoryProxy` | `0xD894A89FdD8d40d3e4708b63f7d9524F3946EC9D` |
| `AnchorStateRegistryProxy` | `0x3eF37ae5Fdb5CbB4cc677CEc6dbecE0648D43439` |
| `DelayedWETHProxy` | `0x4ACb1A9BAff876c9a474866044B190725FBB56E3` |

### Configuration

| Parameter | Value |
|-----------|-------|
| `respectedGameType` | 0 (Cannon) |
| `faultGameAbsolutePrestate` | `0x03a30e81ea09635a211b6f67469ffe9944400437e331b1ec8593ca61d1ab63d2` |
| `faultGameMaxDepth` | 73 |
| `faultGameSplitDepth` | 30 |
| `faultGameMaxClockDuration` | 3600s (1h) |
| `faultGameClockExtension` | 300s (5m) |
| `proofMaturityDelaySeconds` | 12s |
| `faultGameWithdrawalDelay` | 12s |
| `disputeGameFinalityDelaySeconds` | 6s |
| `OP_PROPOSER_PROPOSAL_INTERVAL` | 1800s (30m) |
| `OP_CHALLENGER_TRACE_TYPE` | cannon |

---

## Chain Configuration

| Parameter | Value | Source |
|-----------|-------|--------|
| L2 Block Time | 6s | deploy-config.json |
| L1 Block Time | 12s | deploy-config.json |
| State root proposal period | 30m | `OP_PROPOSER_PROPOSAL_INTERVAL=1800s` (fault proof mode — not l2OutputOracleSubmissionInterval) |
| Challenge Period | 12s | `finalizationPeriodSeconds` |
| Batch submission interval | 24m | `l1BlockTime × OP_BATCHER_MAX_CHANNEL_DURATION = 12 × 120 = 1440s` |
| Withdrawal latency | ~91m 24s | proposal(1800) + game clock(3600) + proof maturity(12) + withdrawal delay(12) = 5424s |

---

## L2 Predeploys (key contracts)

| Contract | Address |
|----------|---------|
| L2CrossDomainMessenger | `0x4200000000000000000000000000000000000007` |
| L2StandardBridge | `0x4200000000000000000000000000000000000010` |
| L2ToL1MessagePasser | `0x4200000000000000000000000000000000000016` |
| L2ERC721Bridge | `0x4200000000000000000000000000000000000014` |
| WETH | `0x4200000000000000000000000000000000000006` |
| L2UsdcBridge | `0x4200000000000000000000000000000000000775` |
| FiatTokenV2_2 (USDC) | `0x4200000000000000000000000000000000000778` |
| LegacyERC20NativeToken (TON) | `0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000` |
