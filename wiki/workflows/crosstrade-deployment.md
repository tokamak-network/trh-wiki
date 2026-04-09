---
updated: 2026-04-10
sources:
  - raw/inbox/crosstrade-deployment-guide.md
related:
  - "[[cross-trade]]"
  - "[[deposit-tx]]"
  - "[[l2-deployment]]"
  - "[[l2-deploy-local]]"
tags: [workflow]
---

# CrossTrade Deployment

새 L2 체인에 CrossTrade 컨트랙트를 배포하고 등록하는 절차. L2-L1 flow와 L2-L2 flow로 나뉘며, 각각 별도의 컨트랙트 세트와 등록 순서가 있다.

> **전제**: Foundry(`forge`, `cast`) 설치 필요. 배포자 주소가 ADMIN_ROLE(`keccak256("ADMIN")`) 보유 확인.

---

## L2-L1 Flow

L1 ↔ L2 간 CrossTrade. L1에 `L1CrossTradeProxy` 하나, 각 L2마다 `L2CrossTradeProxy` 하나.

```
[L2 User] → L2CrossTradeProxy → (CDM) → L1CrossTradeProxy → [L1 Provider]
```

### Step 1 — L1CrossTradeProxy 배포 (최초 1회)

이미 배포된 L1CrossTradeProxy가 있으면 건너뜀.

```bash
PRIVATE_KEY=<key> \
forge script scripts/foundry_scripts/L2L1/DeployL1CrossTrade_L2L1.s.sol \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --broadcast --chain sepolia
```

결과: `L1CrossTradeProxy` + `L1CrossTrade` logic 배포 → `upgradeTo` 완료.

### Step 2 — L2CrossTradeProxy 배포 (각 L2마다)

```bash
L2_CROSS_DOMAIN_MESSENGER=0x4200000000000000000000000000000000000007 \
PRIVATE_KEY=<key> \
forge script scripts/foundry_scripts/L2L1/DeployL2CrossTrade_L2L1.s.sol \
  --rpc-url <L2_RPC_URL> --broadcast
```

OP Stack L2의 CDM 주소는 항상 `0x4200000000000000000000000000000000000007`.

### Step 3 — L1CrossTradeProxy에 L2 등록

```bash
L1_CROSS_TRADE_PROXY=<L1_PROXY> \
L1_CROSS_DOMAIN_MESSENGER=<L2_CDM_L1_ADDR> \
L2_CROSS_TRADE_PROXY=<L2_PROXY> \
L2_CHAIN_ID=<L2_CHAIN_ID> \
PRIVATE_KEY=<key> \
forge script scripts/foundry_scripts/L2L1/SetChainInfoL1_L2L1.sol \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --broadcast --chain sepolia
```

함수 시그니처: `setChainInfo(address CDM, address l2CrossTrade, uint256 chainId)` — 3 params.

### Step 4 — L2CrossTradeProxy에 L1 등록

```bash
L2_CROSS_TRADE_PROXY=<L2_PROXY> \
L1_CROSS_TRADE_PROXY=<L1_PROXY> \
L1_CHAIN_ID=11155111 \
PRIVATE_KEY=<key> \
forge script scripts/foundry_scripts/L2L1/SetChainInfoL2_L2L1.sol \
  --rpc-url <L2_RPC_URL> --broadcast
```

### 검증

```bash
# L1에서 L2 등록 확인
cast call <L1_PROXY> "chainData(uint256)(address,address)" <L2_CHAIN_ID> \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# L2에서 L1 등록 확인
cast call <L2_PROXY> "chainData(uint256)(address,address)" 11155111 \
  --rpc-url <L2_RPC_URL>
```

---

## L2-L2 Flow

L2 ↔ L2 간 CrossTrade. L1에 `L2toL2CrossTradeProxyL1`(허브) 하나, 각 L2마다 `L2toL2CrossTradeProxy` 하나.

```
[L2-A] → L2toL2CrossTradeProxy(A) → (CDM) → L2toL2CrossTradeProxyL1 → (CDM) → L2toL2CrossTradeProxy(B) → [L2-B]
```

### Step 1 — L2toL2CrossTradeProxyL1 배포 (최초 1회, L1에)

이미 배포된 L1 허브가 있으면 건너뜀.

```bash
PRIVATE_KEY=<key> \
forge script scripts/foundry_scripts/DeployL1CrossTrade_L2L2.s.sol \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --broadcast --chain sepolia
```

### Step 2 — L2toL2CrossTradeProxy 배포 (각 L2마다)

```bash
L2_CROSS_DOMAIN_MESSENGER=0x4200000000000000000000000000000000000007 \
PRIVATE_KEY=<key> \
forge script scripts/foundry_scripts/DeployL2CrossTrade_L2L2.s.sol \
  --rpc-url <L2_RPC_URL> --broadcast
```

> **주의**: 배포 직후 `implementation()` 확인. `0x0` 반환 시 `upgradeTo` 미실행 상태 — 별도 upgrade 스크립트 필요.
>
> ```bash
> cast call <L2_PROXY> "implementation()" --rpc-url <L2_RPC_URL>
> ```
>
> L2-L2 flow의 L2 프록시는 `setChainInfo`를 프록시 자체가 직접 구현하지만(implementation 위임 아님),
> 나머지 로직 함수는 implementation에 위임하므로 `upgradeTo` 없이는 동작하지 않는다.

### Step 3 — L2toL2CrossTradeProxyL1에 L2 등록 (L1에서)

함수 시그니처: `setChainInfo(CDM, l2CrossTrade, l2NativeToken, l1Bridge, l1USDCBridge, chainId, useCustomBridge)` — 7 params.

```bash
L1_CROSS_TRADE_PROXY=<L1_HUB_PROXY> \
L1_CROSS_DOMAIN_MESSENGER=<L2_CDM_L1_ADDR> \
L2_CROSS_TRADE_PROXY=<L2_PROXY> \
L2_NATIVE_TOKEN_ADDRESS_ON_L1=<L2_NATIVE_TOKEN_L1_ADDR> \
L1_STANDARD_BRIDGE=<L1_STANDARD_BRIDGE_ADDR> \
L1_USDC_BRIDGE=<L1_USDC_BRIDGE_ADDR> \
USE_CUSTOM_BRIDGE=true \
L2_CHAIN_ID=<L2_CHAIN_ID> \
PRIVATE_KEY=<key> \
forge script scripts/foundry_scripts/SetChainInfoL1_L2L2.sol \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --broadcast --chain sepolia
```

### Step 4 — L2toL2CrossTradeProxy에 L1 허브 등록 (각 L2에서)

```bash
L2_CROSS_TRADE_PROXY=<L2_PROXY> \
L1_CROSS_TRADE_PROXY=<L1_HUB_PROXY> \
L1_CHAIN_ID=11155111 \
PRIVATE_KEY=<key> \
forge script scripts/foundry_scripts/SetChainInfoL2_L2L2.sol \
  --rpc-url <L2_RPC_URL> --broadcast
```

L2에서 L1 허브 등록 확인: `l1CrossTradeContract(uint256)` getter 사용 (L2-L2 프록시는 `chainData`가 아님).

### 검증

```bash
# L1 허브에서 L2 등록 확인
cast call <L1_HUB_PROXY> \
  "chainData(uint256)(address,address,address,address,address,bool)" <L2_CHAIN_ID> \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# L2에서 L1 허브 등록 확인
cast call <L2_PROXY> "l1CrossTradeContract(uint256)" 11155111 \
  --rpc-url <L2_RPC_URL>
```

---

## 새 L2 추가 체크리스트

| # | 작업 | Flow | 실행 체인 | 스크립트 |
|---|------|------|----------|---------|
| 1 | L2CrossTradeProxy 배포 | L2-L1 | L2 | `DeployL2CrossTrade_L2L1.s.sol` |
| 2 | L1CrossTradeProxy에 L2 등록 | L2-L1 | L1 | `SetChainInfoL1_L2L1.sol` |
| 3 | L2CrossTradeProxy에 L1 등록 | L2-L1 | L2 | `SetChainInfoL2_L2L1.sol` |
| 4 | L2toL2CrossTradeProxy 배포 | L2-L2 | L2 | `DeployL2CrossTrade_L2L2.s.sol` |
| 5 | L1 허브에 L2 등록 | L2-L2 | L1 | `SetChainInfoL1_L2L2.sol` |
| 6 | L2toL2CrossTradeProxy에 L1 허브 등록 | L2-L2 | L2 | `SetChainInfoL2_L2L2.sol` |

---

## 현재 Testnet 배포 주소 (Sepolia)

### Network Info

| 체인 | Chain ID | RPC |
|------|----------|-----|
| Sepolia | `11155111` | `https://ethereum-sepolia-rpc.publicnode.com` |
| Thanos Sepolia | `111551119090` | `https://rpc.thanos-sepolia.tokamak.network` |
| ect-defi | `111551190773` | `http://localhost:8545` |

### L2-L1 Flow 주소

| 컨트랙트 | 체인 | 주소 |
|---------|------|------|
| L1CrossTradeProxy | Sepolia | `0xfea37d39bec823d503ed6fb9d3a6e151190821fb` |
| L1CrossTrade (logic) | Sepolia | `0x89e3854f612c12749e58133d52dd5a77d01c1209` |
| L2CrossTradeProxy | Thanos Sepolia | `0xfd2c81fe8a9ceed49c33642cba84bd3cf744bc0e` |
| L2CrossTrade (logic) | Thanos Sepolia | `0xf5472f94e8139460e3d3de97712dd8ed56b6173f` |
| L2CrossTradeProxy | ect-defi | `0xD2Aea5CC4cA8861D809dCb34b354D6059766A809` |

### L2-L2 Flow 주소

| 컨트랙트 | 체인 | 주소 |
|---------|------|------|
| L2toL2CrossTradeProxyL1 (허브) | Sepolia | `0xd038d89655f106d88c5bd56a9442d9ecee675c1c` |
| L2toL2CrossTradeL1 (logic) | Sepolia | `0x1865acb3972ded95c2262358c0bc3a571d18055e` |
| L2toL2CrossTradeProxy | Thanos Sepolia | `0x7bbec445f9bdf6c579e81eada5df86654184bce3` |
| L2toL2CrossTradeL2 (logic) | Thanos Sepolia | `0x344644b3b559af3a26bcb7f65b2b9ce727f5220b` |
| L2toL2CrossTradeProxy | ect-defi | `0x2452ceB66Ccd4B997e3d400F90d42F2566AC0C94` |
| L2toL2CrossTradeL2 (logic) | ect-defi | `0x2a52D7DF50a7F82887bDD4FE96ec8568bd02D3e4` |

### Thanos Sepolia 등록 파라미터 참고 (L2-L2 Step 3)

| 파라미터 | 값 |
|---------|-----|
| L2 CDM (L1 주소) | `0xd3a16d5271f0551ef8a0f393d963878cddecbe00` |
| L2 Native Token (L1 주소) | `0xa30fe40285B8f5c0457DbC3B7C8A280373c40044` |
| L1 Standard Bridge | `0x5D2Ed95c0230Bd53E336f12fA9123847768B2B3E` |
| L1 USDC Bridge | `0x7dD2196722FBe83197820BF30e1c152e4FBa0a6A` |
| Use Custom Bridge | `true` |

---

## 주의사항

- L2-L1 `L1CrossTradeProxy.setChainInfo` = 3 params (CDM, l2CrossTrade, chainId)
- L2-L2 `L2toL2CrossTradeProxyL1.setChainInfo` = 7 params
- Blast API (`eth-sepolia.public.blastapi.io`) 403 발생 가능 — `ethereum-sepolia-rpc.publicnode.com` 사용
- Admin key 없이는 setChainInfo 불가 → 기존 프록시 admin 확인 후 재배포 여부 결정
- `implementation() == 0x0`이면 upgradeTo 미실행 → 모든 로직 호출 reverts

→ [[cross-trade]], [[deposit-tx]]
