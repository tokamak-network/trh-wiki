# Thanos Sepolia Information

Source: Notion page "Thanos Sepolia Information" (ID: 3659fdc0-5b6e-818a-950d-f4a7a82b756d)
Ingested: 2026-05-19
Deployment UUID: 8671124e-6972-42fb-92d2-42edf482a7fd

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

## Endpoint

| Name | URL |
|------|-----|
| L1 RPC (http) | Sepolia |
| L2 RPC (http) | https://rpc.thanos-sepolia.tokamak.network |
| L2 RPC (ws) | wss://rpc.thanos-sepolia.tokamak.network |
| L1 Chain ID | 11155111 |
| L2 Chain ID | 111551132354 |
| Explorer | https://explorer.thanos-sepolia.tokamak.network |
| Bridge | https://bridge.thanos-sepolia.tokamak.network |

All public endpoints route via Cloudflare Tunnel `00637630-de80-402f-8d58-09ad4c53882a` → localhost:8080 (nginx).

---

## L1 Contracts

Deployed on Ethereum Sepolia. Source: deploy-output.json from deployment UUID 8671124e.

| Name | Address |
|------|---------|
| `TON` | `0xa30fe40285B8f5c0457DbC3B7C8A280373c40044` |
| `L1CrossDomainMessengerProxy` | `0xD28D1C8d4017cFb7126Bf501E7C0fFf8aAB3B758` |
| `L1ERC721BridgeProxy` | `0x47e547A05e01f997dc34763F3a50a055b6be1c6f` |
| `L1StandardBridgeProxy` | `0x52A0CCA2600c50B316e382fEb511D4274867B6f0` |
| `DisputeGameFactoryProxy` | `0xD894A89FdD8d40d3e4708b63f7d9524F3946EC9D` |
| `OptimismMintableERC20FactoryProxy` | `0x5048DB3521dbB3CC0487E7C68DB1FFBd2e0bE97E` |
| `OptimismPortalProxy` | `0xf6168f0caC94d88550bB09c7d55C170199eF1d47` |
| `ProxyAdmin` | `0xB7E4D2701D7FD5F4f403aEA0e82bCA2999882251` |
| `SystemConfigProxy` | `0xa22C9EecAE48E192D7280152b322e2681104a537` |
| `AddressManager` | `0x1595516d0F723e6896b300e9ebC8C6489F591abE` |
| `USDC` | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| `USDT` | `0xaa8e23fb1079ea71e0a56f48a2aa51851d8433d0` |
| `L2OutputOracleProxy` | `0x458Fe10728c3E4aB6e0F89ac06D3c2793419aEd8` |
| `SuperchainConfigProxy` | `0xa517f38d26787569138493fe840156d6f9Aa445c` |
| `AnchorStateRegistryProxy` | `0x3eF37ae5Fdb5CbB4cc677CEc6dbecE0648D43439` |
| `DelayedWETHProxy` | `0x4ACb1A9BAff876c9a474866044B190725FBB56E3` |

Note: L2OutputOracleProxy is deployed but unused — useFaultProofs=true, so the proposer submits to DisputeGameFactory.

---

## Chain Configuration

| Name | Value | Calculation |
|------|-------|-------------|
| L2 Block Time | 6s | |
| L1 Block Time | 12s | |
| State root proposal period | 30m | `OP_PROPOSER_PROPOSAL_INTERVAL` = 1800s — Fault Proof mode, L2OutputOracle unused |
| Challenge Period | 12s | `finalizationPeriodSeconds` |
| Batch submission interval | 24m | `l1BlockTime * OP_BATCHER_MAX_CHANNEL_DURATION` = 12 * 120 = 1440s |
| Withdrawal latency | ~91m 24s | Proposal + Game max clock + Proof maturity + Withdrawal delay = 1800+3600+12+12 = 5424s |

---

## Fault Proof

### Contracts

| Name | Address |
|------|---------|
| `DisputeGameFactoryProxy` | `0xD894A89FdD8d40d3e4708b63f7d9524F3946EC9D` |
| `AnchorStateRegistryProxy` | `0x3eF37ae5Fdb5CbB4cc677CEc6dbecE0648D43439` |
| `DelayedWETHProxy` | `0x4ACb1A9BAff876c9a474866044B190725FBB56E3` |

### Configuration

| Name | Value |
|------|-------|
| `respectedGameType` | 0 (Cannon) |
| `faultGameAbsolutePrestate` | `0x03a30e81ea09635a211b6f67469ffe9944400437e331b1ec8593ca61d1ab63d2` |
| `faultGameMaxDepth` | 73 |
| `faultGameSplitDepth` | 30 |
| `faultGameMaxClockDuration` | 3600s (1h) |
| `faultGameClockExtension` | 300s (5m) |
| `faultGameGenesisBlock` | 0 |
| `proofMaturityDelaySeconds` | 12s |
| `faultGameWithdrawalDelay` | 12s |
| `disputeGameFinalityDelaySeconds` | 6s |
| `OP_PROPOSER_PROPOSAL_INTERVAL` | 1800s (30m) |
| `OP_CHALLENGER_TRACE_TYPE` | cannon |

---

## Predeploys (Standard OP Stack)

| No. | Contract Name | Address | Proxy |
|-----|---------------|---------|-------|
| 1 | LegacyMessagePasser | 0x4200000000000000000000000000000000000000 | Proxy |
| 2 | DeployerWhitelist | 0x4200000000000000000000000000000000000002 | Proxy |
| 3 | WETH | 0x4200000000000000000000000000000000000006 | Direct |
| 4 | L2CrossDomainMessenger | 0x4200000000000000000000000000000000000007 | Proxy |
| 5 | GasPriceOracle | 0x420000000000000000000000000000000000000F | Proxy |
| 6 | L2StandardBridge | 0x4200000000000000000000000000000000000010 | Proxy |
| 7 | SequencerFeeVault | 0x4200000000000000000000000000000000000011 | Proxy |
| 8 | OptimismMintableERC20Factory | 0x4200000000000000000000000000000000000012 | Proxy |
| 9 | L1BlockNumber | 0x4200000000000000000000000000000000000013 | Proxy |
| 10 | L2ERC721Bridge | 0x4200000000000000000000000000000000000014 | Proxy |
| 11 | L1Block | 0x4200000000000000000000000000000000000015 | Proxy |
| 12 | L2ToL1MessagePasser | 0x4200000000000000000000000000000000000016 | Proxy |
| 13 | OptimismMintableERC721Factory | 0x4200000000000000000000000000000000000017 | Proxy |
| 14 | ProxyAdmin | 0x4200000000000000000000000000000000000018 | Proxy |
| 15 | BaseFeeVault | 0x4200000000000000000000000000000000000019 | Proxy |
| 16 | L1FeeVault | 0x420000000000000000000000000000000000001A | Proxy |
| 17 | SchemaRegistry | 0x4200000000000000000000000000000000000020 | Proxy |
| 18 | EAS | 0x4200000000000000000000000000000000000021 | Proxy |
| 19 | GovernanceToken | 0x4200000000000000000000000000000000000042 | Direct |
| 20 | ETH | 0x4200000000000000000000000000000000000486 | Direct |
| 21 | QuoterV2 | 0x4200000000000000000000000000000000000500 | Direct |
| 22 | SwapRouter02 | 0x4200000000000000000000000000000000000501 | Direct |
| 23 | UniswapV3Factory | 0x4200000000000000000000000000000000000502 | Direct |
| 24 | NFTDescriptor | 0x4200000000000000000000000000000000000503 | Direct |
| 25 | NonfungiblePositionManager | 0x4200000000000000000000000000000000000504 | Direct |
| 26 | NonfungibleTokenPositionDescriptor | 0x4200000000000000000000000000000000000505 | Proxy |
| 27 | TickLens | 0x4200000000000000000000000000000000000506 | Direct |
| 28 | UniswapInterfaceMulticall | 0x4200000000000000000000000000000000000507 | Direct |
| 29 | UniversalRouter | 0x4200000000000000000000000000000000000508 | Direct |
| 30 | UnsupportedProtocol | 0x4200000000000000000000000000000000000509 | Direct |
| 31 | L2UsdcBridge | 0x4200000000000000000000000000000000000775 | Proxy |
| 32 | SignatureChecker | 0x4200000000000000000000000000000000000776 | Direct |
| 33 | MasterMinter | 0x4200000000000000000000000000000000000777 | Direct |
| 34 | FiatTokenV2_2 (USDC) | 0x4200000000000000000000000000000000000778 | Proxy |
| 35 | LegacyERC20NativeToken (TON) | 0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000 | Direct |
