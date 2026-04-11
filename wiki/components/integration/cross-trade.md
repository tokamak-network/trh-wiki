---
updated: 2026-04-11
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

| 토큰 | L1 주소 (Sepolia) | 브릿지 경로 |
|------|-------------------|------------|
| ETH | address(0) | StandardBridge / OptimismPortal |
| USDC | TBD | L1UsdcBridge → MasterMinter.mint |
| USDT | TBD | StandardBridge (double approval) |

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

---

## L1 setChainInfo (Feature 2)

L2 컨트랙트 배포 완료 후 trh-backend가 직접 실행:

```
L1CrossTradeProxy.setChainInfo(l2ChainId, crossDomainMessenger, l2CrossTradeProxy, nativeToken)
L2toL2CrossTradeL1.setChainInfo(l2ChainId, crossDomainMessenger, l2toL2CrossTradeL2, bridge, usdcBridge, nativeToken)
```

실패 시 최대 3회 재시도 (`retryIntegrationCommon` 패턴). 재시도 실패 시 Electron 알림으로 수동 가이드 제공.

---

## AWS vs Local 공존 원칙

기존 AWS 코드(`DeployCrossTrade()`, Foundry 스크립트, Helm)는 **수정 금지**. 새 로컬 코드는 완전히 별도 파일로 병존한다.

| 환경 | 배포 방식 | dApp 배포 |
|------|---------|---------|
| AWS (K8s) | Foundry 스크립트 | Helm chart |
| Local (Docker) | L1 Deposit Tx (신규) | Docker Compose (신규) |

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

**파일:** `tests/e2e/crosstrade-tx.live.spec.ts` (2026-04-11 기준 CRT-01~07 전체 통과)

| ID | 플로우 | 컨트랙트 |
|----|--------|---------|
| CRT-01 | L1-L2: L2 request | `L2CrossTradeProxy.requestNonRegisteredToken` |
| CRT-02 | L1-L2: L1 provide | `L1CrossTradeProxy.provideCT` |
| CRT-03 | L1-L2: L2 claim | `ProviderClaimCT` event on L2 |
| CRT-04 | L2-L2: L2 request | `L2ToL2CrossTradeProxy.requestNonRegisteredToken` |
| CRT-05 | L2-L2: L1 provide | `L2toL2CrossTradeL1Proxy.provideCT` |
| CRT-06 | L2-L2: L2 claim | `ProviderClaimCT` event on L2 |
| CRT-07 | dApp UI 스크린샷 | EIP-6963 mock provider 주입 |

**가스 정책:**
- L1 `provideCT` (L1→L2): explicit gasLimit 없음, ethers.js 자동 추정
- L1 `provideCT` (L2→L2): explicit gasLimit 없음, 자동 추정 (~800k; CDM 2회 처리)
- `_minGasLimit` (CDM relay용): `200_000` 고정

→ [[testing]], [[l1-gas-limits]]
