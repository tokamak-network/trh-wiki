---
updated: 2026-04-09
sources:
  - raw/decisions/PRD-CrossTrade-TRH-Integration-v2.1.md
  - raw/decisions/Genesis-Predeploy-Storage-Analysis.md
related:
  - "[[deposit-tx]]"
  - "[[cross-trade]]"
  - "[[trh-sdk]]"
tags: [decision]
---

# Decision: L1 Deposit Tx vs Genesis Predeploy

**결정:** L2 CrossTrade 컨트랙트 배포 방식으로 **L1 Deposit Transaction** 채택.

---

## 배경

CrossTrade L2 컨트랙트를 배포하는 방법은 두 가지가 있다:

1. **Genesis Predeploy**: L2 genesis의 `alloc` 필드에 bytecode + storage를 직접 지정
2. **L1 Deposit Tx**: `OptimismPortal.depositTransaction()`으로 L1에서 L2 컨트랙트를 생성

---

## Genesis Predeploy를 거부한 이유

### 이유 1: Constructor가 실행되지 않는다

Genesis `alloc`에 bytecode를 직접 넣으면 constructor가 실행되지 않는다. L2CrossTradeProxy의 constructor는 다음을 수행한다:

```solidity
constructor() {
    _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    _grantRole(ADMIN_ROLE, msg.sender);
}
```

이것이 실행되지 않으면 **모든 `onlyOwner` 함수 호출이 불가능**해진다:
- `initialize()`, `setChainInfo()`, `registerToken()`
- `upgradeTo()`, `setSelectorImplementations2()`

### 이유 2: 15개 스토리지 슬롯을 수동 계산해야 한다

컴파일러 검증으로 확인된 필수 슬롯:

| 카테고리 | 슬롯 수 | 설명 |
|---------|--------|------|
| AccessControl `_roles` | 2개 | ADMIN_ROLE admin + member 설정 |
| ReentrancyGuard `_status` | 1개 | `NOT_ENTERED = 1` |
| Proxy 패턴 | 2개 | `proxyImplementation[0]`, `aliveImplementation[impl]` |
| Selector 매핑 | 7개 | 모든 public 함수의 bytes4 selector |
| 데이터 필드 | 3개 | `crossDomainMessenger`, `NATIVE_TOKEN`, `chainData` |

총 **15개 슬롯**. 슬롯 계산 공식:
```
mapping value → keccak256(abi.encode(key, slotNumber))
bytes32 → 직접 slot 번호
```

L2CrossTrade + L2toL2CrossTrade 두 컨트랙트에 각각 적용하면 30개+.

### 이유 3: Mainnet에서 Bridge Invariant 위반

Genesis predeploy로 배포된 컨트랙트는 L1 Bridge가 인식하지 못한다. `depositTransaction()`을 통한 정상 배포와 달리, genesis alloc에 직접 넣은 컨트랙트는 OptimismPortal의 상태 검증에서 누락된다. **Mainnet에서 자금 손실 위험.**

---

## L1 Deposit Tx를 선택한 이유

| 이점 | 설명 |
|------|------|
| Constructor 정상 실행 | AccessControl, ReentrancyGuard 초기화 자동 처리 |
| 표준 배포 흐름 | 일반 L2 컨트랙트 배포와 동일 — 이미 검증된 패턴 |
| Bridge 안전성 | L1→L2 메시지 큐 경유 → OptimismPortal 상태 추적 가능 |
| 코드 단순성 | Storage slot 수동 계산 코드 불필요 |
| go-ethereum 호환 | `bind.WaitMined`, `abi.Pack` — SDK 기존 패턴 그대로 사용 |

---

## 트레이드오프

| 항목 | Genesis Predeploy | L1 Deposit Tx |
|------|------------------|---------------|
| 배포 속도 | 즉시 (genesis 포함) | ~5분 (12 tx) |
| 구현 복잡도 | 매우 높음 (slot 계산) | 낮음 (기존 SDK 패턴) |
| Mainnet 안전성 | 위험 (bridge invariant) | 안전 |
| L2 주소 예측 | 사전에 알 수 있음 | nonce 기반 예측 필요 |
| 배포 실패 복구 | 불가 (genesis 재생성 필요) | 개별 tx 재시도 가능 |

---

## 참고

- `Genesis-Predeploy-Storage-Analysis.md` — solc 0.8.24 storageLayout 검증 결과
- PRD v2.0 → v2.1 전환의 핵심 결정사항
