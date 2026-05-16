---
updated: 2026-05-10
sources:
  - raw/decisions/PRD-CrossTrade-TRH-Integration-v2.1.md
  - raw/inbox/crosstrade-deployment-guide.md
related:
  - "[[deposit-tx]]"
  - "[[l2-deployment]]"
  - "[[presets]]"
  - "[[trh-sdk]]"
  - "[[trh-backend]]"
  - "[[deposit-tx-vs-genesis-predeploy]]"
  - "[[separate-compose-for-crosstrade]]"
  - "[[l1-deposit-tx-pitfalls]]"
tags: [component]
---

# CrossTrade

L2 운영자가 7일 출금 대기 없이 빠른 크로스체인 토큰 교환을 제공할 수 있는 프로토콜. DeFi/Full Preset에서 자동 배포된다.

---

## Preset 매핑

| Preset | CrossTrade 활성화 |
|--------|-----------------|
| General | ❌ |
| DeFi | ✅ |
| Gaming | ❌ |
| Full | ✅ |

---

## 컨트랙트 구조

### L1 컨트랙트 (기존 배포, Sepolia에 고정)

| 컨트랙트 | 역할 |
|---------|------|
| L1CrossTradeProxy | L2→L1 크로스트레이드 진입점 |
| L2toL2CrossTradeL1 | L2→L2 크로스트레이드 L1 측 |

### L2 컨트랙트 (L1 Deposit Tx로 배포)

| 컨트랙트 | 역할 | 배포 방식 |
|---------|------|---------|
| L2CrossTrade (impl) | L2→L1 크로스트레이드 로직 | L1 Deposit Tx (contract creation) |
| L2CrossTradeProxy | L2→L1 크로스트레이드 프록시 | L1 Deposit Tx (contract creation) |
| L2toL2CrossTradeL2 (impl) | L2→L2 크로스트레이드 로직 | L1 Deposit Tx (contract creation) |
| L2toL2CrossTradeProxy | L2→L2 크로스트레이드 프록시 | L1 Deposit Tx (contract creation) |

---

## 배포 시퀀스 (12 트랜잭션)

```
1. L2CrossTrade impl 배포        (Deposit Tx, contract creation)
2. L2CrossTradeProxy 배포        (Deposit Tx, contract creation)
3. setSelectorImplementations2   (Deposit Tx, proxy 설정)
4. initialize                    (Deposit Tx, proxy 초기화)
5. setChainInfo (L2→L1)         (Deposit Tx, L1 체인 등록)
6. registerToken × N             (Deposit Tx, 토큰 등록)
7. L2toL2CrossTradeL2 impl 배포  (Deposit Tx, contract creation)
8. L2toL2CrossTradeProxy 배포    (Deposit Tx, contract creation)
9. setSelectorImplementations2   (Deposit Tx, proxy 설정)
10. initialize                   (Deposit Tx, proxy 초기화)
11. setChainInfo (L2→L2)        (Deposit Tx, L1 체인 등록)
12. registerToken × N            (Deposit Tx, 토큰 등록)
```

→ [[deposit-tx]] 참고

---

## 지원 토큰 (DeFi/Full Preset 기본값)

| 토큰 | L1 주소 (Sepolia) | L2 주소 | 브릿지 경로 |
|------|-------------------|---------|------------|
| ETH | `address(0)` | `address(0)` | StandardBridge / OptimismPortal |
| USDC | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` | `0x4200000000000000000000000000000000000778` | Thanos genesis predeploy (L2) |
| USDT | TBD | TBD | TBD — `TODO(usdt)` 주석으로 표시됨 |

**USDC L2 주소 출처:** Thanos genesis predeploy `0x4200...0778`. `deployment.go` `autoInstallCrossTradeLocal()` 에서 `TokenPair` 슬라이스에 고정값으로 등록됨 (2026-04-18 확정).

**USDC ERC20 approve 필요:** ETH와 달리 USDC는 `requestNonRegisteredToken` 호출 전에 `approve(crossTradeProxy, amount)` 선행 필요. `{ value: amount }` 없이 호출.

---

## 코드 위치

| 파일 | 역할 |
|------|------|
| `trh-sdk/pkg/stacks/thanos/cross_trade_local.go` | SDK 진입점 (신규, local 전용) |
| `trh-sdk/pkg/stacks/thanos/cross_trade.go` | AWS 방식 기존 코드 (수정 금지) |
| `trh-backend/pkg/services/thanos/integrations/cross_trade_local.go` | L1 setChainInfo, dApp 환경변수 생성 |
| `trh-backend/pkg/services/thanos/stack_lifecycle.go` | `localUnsupported["crossTrade"]` 제거 필요 |
| `trh-backend/pkg/services/thanos/deployment.go` | auto-install 블록에 CrossTrade 추가 |

---

## dApp 서비스

- 이미지: `tokamaknetwork/cross-trade-dapp`
- 포트: `3001:3000`
- 별도 compose 파일: `docker-compose.crosstrade.yml`
- 환경 변수: `config/.env.crosstrade` (배포 완료 후 Backend가 자동 생성)

→ [[separate-compose-for-crosstrade]]

### 환경 변수 포맷 (2026-04-15 기준)

dApp은 세 개의 env var를 읽는다:

| 변수 | 역할 |
|------|------|
| `NEXT_PUBLIC_PROJECT_ID` | WalletConnect project ID |
| `NEXT_PUBLIC_CHAIN_CONFIG_L2_L1` | L2→L1 모드용 체인 설정 (snake_case, flat token map) |
| `NEXT_PUBLIC_CHAIN_CONFIG_L2_L2` | L2→L2 모드용 체인 설정 (array-of-token 포맷) |

> **이전 이름 (`NEXT_PUBLIC_CHAIN_CONFIG`) 은 더 이상 사용하지 않는다.** trh-sdk `local-compose.yml.tmpl`도 이에 맞게 수정됨 (commit `8af71e6`).

**L2_L2 체인 설정 토큰 포맷** (array-of-object, destination_chains 포함):
```json
{
  "17001": {
    "name": "...", "rpc_url": "...", "contracts": {...},
    "tokens": [
      {"name": "ETH", "address": "0x000...000", "destination_chains": [111551119090]},
      {"name": "USDC", "address": "0x420...778", "destination_chains": [111551119090]}
    ]
  }
}
```

**L2_L1 체인 설정 토큰 포맷** (flat map):
```json
{
  "17001": {
    "rpc_url": "http://host.docker.internal:9545",
    "tokens": {"ETH": "0x000...000", "USDC": "0x420...778"}
  }
}
```

---

## L1 setChainInfo (Feature 2)

L2 컨트랙트 배포 완료 후 trh-backend가 직접 실행:

```
L1CrossTradeProxy.setChainInfo(l2ChainId, crossDomainMessenger, l2CrossTradeProxy, nativeToken)
L2toL2CrossTradeL1.setChainInfo(l2ChainId, crossDomainMessenger, l2toL2CrossTradeL2, bridge, usdcBridge, nativeToken)
```

실패 시 최대 3회 재시도 (`retryIntegrationCommon` 패턴). 재시도 실패 시 Electron 알림으로 수동 가이드 제공.

---

## AWS vs Local 배포 방식

| 환경 | L2 컨트랙트 배포 | dApp 배포 |
|------|---------|---------|
| AWS (K8s) | L1 Deposit Tx (`DeployCrossTradeLocal`) | Helm chart (inline, `installCrossTradeHelmAWS`) |
| Local (Docker) | L1 Deposit Tx (`DeployCrossTradeLocal`) | Docker Compose |

### AWS 자동 설치 (`cross_trade_aws.go`)

DeFi/Full preset AWS 배포 시 trh-backend goroutine이 `AutoInstallCrossTradeAWS`를 자동 호출한다 (SDK `installPresetModules`는 이 경로 처리 안 함):

1. `readDeploymentContracts()` — `deploy-output.json`에서 `OptimismPortalProxy`, `L1CrossDomainMessengerProxy` 읽기
2. `DeployCrossTradeLocal` — L1 Deposit Tx로 L2 CrossTrade 컨트랙트 배포 (20-40분)
3. `installCrossTradeHelmAWS` — 단일 CrossTrade Helm 릴리스 배포, ALB ingress 대기

**단일 릴리스 구조 (2026-05-10):** L2→L1과 L2→L2를 각각 별도 Helm 릴리스로 배포하던 방식에서 **단일 릴리스**로 통합. dApp이 `getCommunicationMode()`로 도착 체인 기반 자동 모드 분기하므로 두 체인 config(`NEXT_PUBLIC_CHAIN_CONFIG_L2_L1` + `NEXT_PUBLIC_CHAIN_CONFIG_L2_L2`)를 하나의 릴리스에 모두 주입하는 것으로 충분. ALB group name: `"cross-trade"` 하나.

**`AutoInstallCrossTradeAWSOutput` 구조:**
- `DAppURL string` — 단일 dApp ALB URL (이전: `L2L1DAppURL`/`L2L2DAppURL` 두 필드)
- `L2CrossTradeProxy`, `L2toL2CrossTradeProxy`, `L1CrossTradeProxy`, `L2toL2CrossTradeL1` — 컨트랙트 주소

**Backend metadata 저장:** `finalMetadata["url"] = output.DAppURL` + `stack.Metadata.CrossTradeUrl` — Integration UI의 `integration.info?.url` 키와 매핑됨.

**주의:** `DeployCrossTradeApplication` 함수는 `input.L2ChainConfig[l2ChainID]`에서 uint64 체인 ID를 슬라이스 인덱스로 사용하는 버그가 있다 (e.g. 111551215120 → 즉시 panic). AWS 경로는 이 함수를 우회하여 Helm 로직을 inline으로 구현한다.

### L1 CrossTrade 컨트랙트 주소 (Sepolia)

Tokamak 팀이 배포한 공유 인프라 — 모든 L2 체인이 동일한 L1 컨트랙트 사용:

| 컨트랙트 | 주소 |
|---------|------|
| L1CrossTradeProxy | `0xf3473E20F1d9EB4468C72454a27aA1C65B67AB35` |
| L2toL2CrossTradeL1 | `0xDa2CbF69352cB46d9816dF934402b421d93b6BC2` |

---

## dApp 알려진 버그 및 설계 결정

### Thanos Sepolia → 신규 L2 방향 비활성화

**증상:** Thanos Sepolia를 source로 선택하고 신규 L2를 destination으로 설정하면, OKX 같은 지갑이 서명 팝업을 전혀 띄우지 않는다 ("서명이 안된다").

**근본 원인:** 지갑(OKX 포함)은 서명 팝업 전에 `eth_estimateGas`로 트랜잭션을 사전 시뮬레이션한다. Thanos Sepolia의 `L2toL2CrossTradeProxy(0x7BbEC445F9BDF6c579e81EAda5df86654184BcE3)`는 Tokamak 팀이 관리하는 프록시로, 우리가 배포한 신규 L2 체인 ID가 등록되어 있지 않다. 따라서 시뮬레이션 단계에서 컨트랙트가 revert → 지갑이 팝업 자체를 차단한다.

**해결책 1 — destination 숨김 (2026-04-15):** trh-backend `BuildDAppEnvConfig()`에서 Thanos Sepolia 토큰의 `destination_chains`를 `[]` (빈 배열)로 설정. dApp destination picker는 `destination_chains`가 빈 체인을 후보에서 제외하므로, 사용자가 Thanos→신규L2 경로에 도달하지 못하게 된다.

**해결책 2 — UI 안내 메시지 (2026-04-18):** destination picker 아래에 안내 문구 추가. `getAllowedDestinationChains().length === 0` 조건 (= Thanos Sepolia가 source일 때) 이면 `<p data-testid="thanos-direction-notice">Thanos Sepolia → [your L2] direction is not yet available. Only [your L2] → Thanos Sepolia bridging is supported.</p>` 렌더링.

**코드:**
- `trh-backend/pkg/services/thanos/integrations/cross_trade_local.go` — `thanosL2L2Tokens` 세 항목(ETH, TON, USDC) 모두 `DestinationChains: []uint64{}`
- `crossTrade/frontend/cross-trade-dapp/src/components/CreateRequest.tsx` — destination picker 아래 `thanos-direction-notice` 조건부 렌더링

**반대 방향(신규L2 → Thanos Sepolia)은 정상 동작.** 신규 L2의 `L2toL2CrossTradeProxy`에는 우리가 admin이므로 Thanos Sepolia 체인 ID를 등록할 수 있다. `destination_chains: [111551119090]`으로 설정되어 있다.

### destination picker에서 L1 체인이 누락되는 문제

**증상 (defi-eth 프리셋):** L2 → Sepolia (출금) 플로우에서 destination 드롭다운에 Sepolia가 나타나지 않는다.

**근본 원인:** `getAllowedDestinationChains()`가 `L2_L2` config의 `destination_chains`만 조회했다. `requestTo`가 비어 있을 때 `getCommunicationMode()`가 항상 `L2_L2`를 반환하므로, Sepolia(L1)는 `L2_L2` config에 없어 항상 걸러졌다.

**해결책 (2026-04-15):** `getAllowedDestinationChains()`를 mode-agnostic하게 변경 — `L2_L2`와 `L2_L1` 양쪽 destination을 union으로 반환. 사용자가 Sepolia를 선택하는 순간 `getCommunicationMode()`가 자동으로 `L2_L1`로 전환된다.

**코드:** `crossTrade/frontend/cross-trade-dapp/src/components/CreateRequest.tsx` — `getAllowedDestinationChains()` 함수

### Fee token 라벨 불일치 (polymorphic native token)

**증상:** fee token이 ETH/USDT/USDC가 아닌 경우 CrossTrade dApp L2→L1 모드에서 native token이 "TON"으로 잘못 표시되고, USDT/TON 스택에서는 dropdown에서 native token이 아예 사라지고 "eth"가 첫 원소로 잡힌다.

**3계층 불일치:**

| Layer | 잘못된 동작 | 올바른 동작 |
|-------|------------|-----------|
| Backend metadata | `native_token_symbol="TON"` (ETH 이외 모두 디폴트) | fee token symbol 그대로 |
| Token map | `l2l1Tokens["USDT"]=""` (빈 주소) → dApp이 항목 제외 | `{"USDT": "0x0000..."}` (native = zero addr) |
| dApp 표시 | `sendToken state = "eth"` (ETH가 첫 원소) | `sendToken state = fee token symbol` |

**근본 원인:** `deployment.go`가 ETH만 명시적으로 `L2NativeTokenName/Symbol`을 설정하고 나머지는 모두 `cross_trade_local.go`의 "Tokamak Network"/"TON" 하드코딩 디폴트로 폴백. 또한 `l2l1Tokens` / `l2l2Tokens`가 USDT·TON에 빈 문자열 주소를 가졌음.

**해결책 (2026-05-17):** 

- `CrossTradeDAppConfig`에 `FeeTokenSymbol` 필드 추가.
- `buildL2L1Tokens(feeSymbol)` / `buildL2L2Tokens(feeSymbol, destChain)` helper 도입 — native gas token은 항상 zero address, USDC ERC20 predeploy(`0x4200...0778`)는 fee token이 USDC가 아닐 때만 추가.
- `BuildDAppEnvConfig`에서 `feeSymbol` 기반 switch로 `native_token_name`/`native_token_symbol` 파생 (ETH→Ethereum, USDT→Tether USD, USDC→USD Coin, default→Tokamak Network/TON).
- `deployment.go` 두 호출처에서 ETH-only if 블록 제거 → `FeeTokenSymbol: stackConfig.FeeToken` 전달.
- dApp 변경 없음 — 백엔드가 올바른 tokens 배열의 첫 원소를 fee token으로 보내면 기존 `useState(tokens[0].name)` 로직이 자동 해결.

**Token 매핑 결과:**

| Fee Token | native_token_symbol | L2 Tokens (L2L1/L2L2) |
|-----------|---------------------|----------------------|
| ETH | ETH | `{ETH: 0x0000…, USDC: 0x4200…0778}` |
| USDT | USDT | `{USDT: 0x0000…, USDC: 0x4200…0778}` |
| TON | TON | `{TON: 0x0000…, USDC: 0x4200…0778}` |
| USDC | USDC | `{USDC: 0x0000…}` (ERC20 USDC 중복 제외) |

---

## 루트 원인 수정 (2026-04-19 CRT E2E 런)

CRT-01~10 전체 실행에서 발견된 세 가지 SDK/Backend 버그. 모두 수정 완료.

### Fix 1: L1CrossDomainMessengerProxy.initialize() 미호출 (CDM portal=0x0)

**증상 (CRT-02):** `L1CrossDomainMessengerProxy.PORTAL()` 조회 결과 `0x0`. `provideCT` 실행 시 CDM 메시지 전달 불가.

**근본 원인:** tokamak-deployer는 `upgrade(proxy, impl)` 만 호출하고 `initialize(superchainConfig, portal, systemConfig)` 를 호출하지 않는다. 프록시 스토리지의 `portal` 슬롯이 0으로 남아 CDM이 실질적으로 비활성 상태.

**해결책:** `trh-sdk/pkg/stacks/thanos/deploy_chain.go` 에 `initL1CrossDomainMessenger()` 함수 추가.
- 멱등성 가드: `portal()` 슬롯을 raw call로 읽어 non-zero면 건너뜀
- pre-flight: `eth_call` 시뮬레이션 후 TX 전송 (gasLimit=300,000, gasPrice×2)
- ABI 인코딩: `keccak256("initialize(address,address,address)")[:4]` + 32바이트 패딩 주소 × 3 = 100바이트

`local_network.go` 에서 genesis anchor 초기화 블록 이후 즉시 호출됨 (`EnableFraudProof` 조건 밖).

**파일:**
- `trh-sdk/pkg/stacks/thanos/deploy_chain.go` — `initL1CrossDomainMessenger()` 신규 함수
- `trh-sdk/pkg/stacks/thanos/local_network.go` — `readDeploymentContracts()` 외부로 이동, CDM init 호출 추가
- `trh-sdk/pkg/stacks/thanos/deploy_chain_test.go` — `TestInitL1CrossDomainMessengerCalldataEncoding` (패딩 검증 포함)

---

### Fix 2: deployL2CrossTradePair L2CDM 주소 오류

**증상:** `L2ToL2CrossTradeProxy.crossDomainMessenger()` 가 L2CDM predeploy(`0x4200...0007`)가 아닌 L1CDM 주소를 반환. L2→L2 provide/claim 메시지 릴레이 실패.

**근본 원인:** `cross_trade_local.go` `deployL2CrossTradePair()` 가 `initialize()` 호출 시 `input.CrossDomainMessenger`(L1CDM 주소)를 L2CDM 파라미터로 전달했다.

**해결책:** `trh-sdk/pkg/stacks/thanos/cross_trade_local.go` 의 해당 줄을 L2CDM predeploy 상수로 교체.
```go
// Before:
common.HexToAddress(input.CrossDomainMessenger),
// After:
common.HexToAddress("0x4200000000000000000000000000000000000007"), // L2CDM predeploy
```

**파일:**
- `trh-sdk/pkg/stacks/thanos/cross_trade_local.go` — L2CDM 인수 고정값으로 교체
- `trh-sdk/pkg/stacks/thanos/cross_trade_local_test.go` — `TestL2CDMPredeploy_IsNotZero` 신규

---

### Fix 3: L1UsdcBridgeAdapter — Circle bridgeERC20To vs depositERC20To 불일치

**증상 (CRT-09):** `L1CrossTradeProxy.provideCT()`가 내부적으로 `IL1StandardBridge.bridgeERC20To(...)` selector를 호출하는데, Circle의 L1UsdcBridge는 `depositERC20To(...)` selector를 노출한다. 직접 호출 시 함수 selector 불일치로 revert.

**근본 원인:** CrossTrade SDK는 L1 브리지로 `IL1StandardBridge` 인터페이스를 가정한다. Circle USDC 브리지는 이 인터페이스를 구현하지 않는다.

**해결책:** `L1UsdcBridgeAdapter.sol` 어댑터 배포. `bridgeERC20To` 를 받아 `depositERC20To` 로 위임. trh-backend `RegisterCrossTradeL2()` 가 `input.L1USDCBridge` 가 있을 때 어댑터를 프로그래매틱으로 배포하고, `setChainInfo` 에 원래 L1UsdcBridge 대신 어댑터 주소를 전달.

```
CrossTrade → L1UsdcBridgeAdapter.bridgeERC20To(l1, l2, to, amount, gasLimit, data)
                    ↓ safeTransferFrom + forceApprove
             L1UsdcBridge.depositERC20To(l1, l2, to, amount, gasLimit, data)
```

**어댑터 배포 방식:** constructor ABI 인코딩은 `copy(constructorArg[12:32], l1UsdcBridgeAddr.Bytes())` (left-pad 20바이트 → 32바이트 슬롯). 컴파일된 바이트코드는 `l1UsdcBridgeAdapterBytecode` 상수로 인라인.

**파일:**
- `crossTrade/contracts/L1/L1UsdcBridgeAdapter.sol` — 신규 어댑터 컨트랙트
- `trh-backend/pkg/services/thanos/integrations/cross_trade_local.go` — `deployL1UsdcBridgeAdapter()` + `RegisterCrossTradeL2()` 조건부 배포 로직
- `trh-backend/pkg/services/thanos/integrations/cross_trade_local_test.go` — `TestDeployL1UsdcBridgeAdapterBytecodeEncoding`

---

## 운영 함정

### Admin key 없으면 기존 프록시 재사용 불가

CrossTrade 프록시(L1CrossTradeProxy, L2CrossTradeProxy 등)의 `setChainInfo`는 ADMIN_ROLE(`keccak256("ADMIN")`) 보유자만 호출 가능. 최초 deployer 주소가 ADMIN_ROLE을 갖고 있으며, 그 private key를 잃으면 해당 프록시에 새 체인을 등록하는 것이 **영구적으로 불가능**하다.

실제 사례(2026-04-10): 기존 `L1CrossTradeProxy(0x00a13E2...)` 및 Thanos `L2CrossTradeProxy(0x54bc...)` 모두 원래 deployer(`0xb4032ff...`)의 key가 없어 새 체인 등록 불가 → 전체 재배포.

**사전 체크**: 배포 전 `isAdmin(ourAddress)` 호출로 권한 확인.

### L2-L2 프록시 setChainInfo — proxy-direct 구현의 함정

`L2toL2CrossTradeProxy.setChainInfo`는 implementation에 위임하지 않고 **proxy 자체에 직접 구현**되어 있다. 이 때문에 `implementation() == 0x0`인 상태(upgradeTo 미실행)에서도 `setChainInfo` 호출은 성공한다.

문제: 나머지 모든 비즈니스 로직 함수는 implementation에 위임되므로, upgradeTo 없이 setChainInfo만 실행된 프록시는 **체인 등록은 되어 있지만 실제 기능은 전혀 동작하지 않는** 상태가 된다. `chainData()` 같은 조회 함수조차 "Proxy: impl OR proxy is false"로 revert.

→ [[l1-deposit-tx-pitfalls]] Pitfall #14 참고

---

## E2E 테스트

### crosstrade-tx.live.spec.ts (CRT-01~10)

**파일:** `tests/e2e/crosstrade-tx.live.spec.ts`

| ID | 플로우 | 컨트랙트 | 상태 |
|----|--------|---------|------|
| CRT-01 | L1-L2: L2 request (ETH) | `L2CrossTradeProxy.requestNonRegisteredToken` | ✅ |
| CRT-02 | L1-L2: L1 provide (ETH) | `L1CrossTradeProxy.provideCT` | ✅ |
| CRT-03 | L1-L2: L2 claim (ETH) | `ProviderClaimCT` event on L2 | ✅ |
| CRT-04 | L2-L2: L2 request (ETH) | `L2ToL2CrossTradeProxy.requestNonRegisteredToken` | ✅ |
| CRT-05 | L2-L2: L1 provide (ETH) | `L2toL2CrossTradeL1Proxy.provideCT` | ✅ |
| CRT-06 | L2-L2: L2 claim (ETH) | `ProviderClaimCT` event on L2 | ✅ |
| CRT-07 | dApp UI 스크린샷 | EIP-6963 mock provider 주입 | ✅ |
| CRT-08 | L2→L1: L2 request (USDC) | `approve` + `requestNonRegisteredToken` (no value) | ✅ |
| CRT-09 | L2→L1: L1 provide (USDC) | L1 `approve` + `provideCT` via L1UsdcBridgeAdapter | ✅ |
| CRT-10 | L2→L1: L2 claim (USDC) | `ProviderClaimCT._l2token == USDC` 검증 | ✅ |

**USDC 상수 (CRT-08~10):**
- `USDC_L1_ADDRESS`: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
- `USDC_L2_ADDRESS`: `0x4200000000000000000000000000000000000778`
- `USDC_TRADE_AMOUNT` / `USDC_CT_AMOUNT`: `1_000_000` (1 USDC, 6 decimals)

### 08-defi-crosstrade-electron.spec.ts (CT-E2E-01~05)

**파일:** `tests/e2e/08-defi-crosstrade-electron.spec.ts` (2026-04-18 신규)

| ID | 플로우 | 설명 | 상태 |
|----|--------|------|------|
| CT-E2E-01 | Electron 배포 | DeFi preset UI 통해 전체 L2 배포 | ✅ SKIP (SKIP_DEPLOY=true 재사용) |
| CT-E2E-02 | CrossTrade 설치 확인 | port 3004 HTTP + USDC 주소 HTML 포함 여부 | ✅ |
| CT-E2E-03 | ETH 크로스트레이드 | `requestNonRegisteredToken(ETH, value)` | ✅ saleCount: 8 |
| CT-E2E-04 | USDC 크로스트레이드 | `approve` + `requestNonRegisteredToken(USDC)` | ✅ saleCount: 9 |
| CT-E2E-05 | Thanos 방향 UI | mock wallet 주입 → `thanos-direction-notice` visible | ✅ `hasAnyL2L2Destinations()` 조건 수정 후 통과 |

**가스 정책:**
- L1 `provideCT` (L1→L2): explicit gasLimit 없음, ethers.js 자동 추정
- L1 `provideCT` (L2→L2): explicit gasLimit 없음, 자동 추정 (~800k; CDM 2회 처리)
- `_minGasLimit` (CDM relay용): `200_000` 고정

→ [[testing]], [[l1-gas-limits]]
