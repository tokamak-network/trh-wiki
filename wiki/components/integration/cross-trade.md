---
updated: 2026-04-10
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
  - "[[crosstrade-deployment]]"
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

## Testnet 배포 주소 (Sepolia, 2026-04-10 기준)

### L2-L1 Flow

| 컨트랙트 | 체인 | 주소 |
|---------|------|------|
| L1CrossTradeProxy | Sepolia | `0xfea37d39bec823d503ed6fb9d3a6e151190821fb` |
| L2CrossTradeProxy | Thanos Sepolia | `0xfd2c81fe8a9ceed49c33642cba84bd3cf744bc0e` |
| L2CrossTradeProxy | ect-defi (111551190773) | `0xD2Aea5CC4cA8861D809dCb34b354D6059766A809` |

### L2-L2 Flow

| 컨트랙트 | 체인 | 주소 |
|---------|------|------|
| L2toL2CrossTradeProxyL1 (허브) | Sepolia | `0xd038d89655f106d88c5bd56a9442d9ecee675c1c` |
| L2toL2CrossTradeProxy | Thanos Sepolia | `0x7bbec445f9bdf6c579e81eada5df86654184bce3` |
| L2toL2CrossTradeProxy | ect-defi (111551190773) | `0x2452ceB66Ccd4B997e3d400F90d42F2566AC0C94` |

> 기존 L1CrossTradeProxy(`0x00a13E2...`) 및 Thanos L2CrossTradeProxy(`0x54bc...`)는 admin key 미확보로 재배포됨.
> 배포 및 등록 순서 전체 가이드 → [[crosstrade-deployment]]
