---
updated: 2026-04-09
sources:
  - raw/decisions/PRD-CrossTrade-TRH-Integration-v2.1.md
related:
  - "[[cross-trade]]"
  - "[[l2-deployment]]"
  - "[[trh-sdk]]"
  - "[[l1-gas-limits]]"
  - "[[deposit-tx-vs-genesis-predeploy]]"
tags: [concept]
---

# Deposit Transaction (L1 → L2)

OP Stack의 `OptimismPortal.depositTransaction()`을 호출해 L1 트랜잭션을 L2에서 실행시키는 메커니즘.

---

## 핵심 개념

L1에서 `depositTransaction()` 호출 → L2에서 해당 calldata가 자동 실행됨. L2 컨트랙트 생성(`isCreation=true`)과 함수 호출(`isCreation=false`) 모두 가능하다.

EOA가 `OptimismPortal.depositTransaction()`을 직접 호출하는 경우, **L2 sender 주소 = L1 EOA 주소** (aliasing 없음).

---

## OptimismPortal.depositTransaction() 파라미터

| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `_to` | address | L2에서의 수신 주소. `isCreation=true`이면 `address(0)` |
| `_value` | uint256 | L2에서 전송할 ETH 금액 (wei) |
| `_gasLimit` | uint64 | L2 실행 가스 한도 |
| `_isCreation` | bool | `true` = 컨트랙트 생성, `false` = 함수 호출 |
| `_data` | bytes | `isCreation=true`이면 bytecode, `false`이면 calldata |

---

## L2 컨트랙트 주소 예측

Contract creation은 표준 EVM CREATE 공식을 따른다:

```
L2 컨트랙트 주소 = CREATE(sender=L1_EOA_address, nonce=L2_nonce)
```

단, L2 nonce는 배포 시점의 L2 상태에 따라 결정된다. Deposit Tx가 실패하면 이후 모든 nonce 예측이 틀어지므로, 각 단계를 순서대로 실행하고 실패 시 롤백/재시도 로직이 필요하다.

---

## Gas Limit 가이드

| 오퍼레이션 | L1 가스 | L2 가스 한도 |
|-----------|--------|------------|
| depositTransaction (contract creation) | ~100k–150k | 3,000,000 |
| depositTransaction (function call) | ~60k–80k | 500,000 |
| setSelectorImplementations2 | ~60k–80k | 1,000,000 |
| initialize | ~60k–80k | 1,000,000 |

→ [[l1-gas-limits]] 참고

---

## SDK 구현 패턴

trh-sdk에서의 사용 패턴:

```go
// abigen 바인딩으로 OptimismPortal 호출
portal, _ := abis.NewOptimismPortal(portalAddr, client)
tx, err := portal.DepositTransaction(txOpts, to, value, gasLimit, isCreation, data)
receipt, _ := bind.WaitMined(ctx, client, tx)

// L2 calldata는 abi.Pack으로 직접 인코딩
abi, _ := abi.JSON(strings.NewReader(L2CrossTradeABI))
data, _ := abi.Pack("initialize", arg1, arg2, ...)
```

→ [[abigen-vs-manual-calldata]]

---

## Receipt 확인

L1 Deposit Tx receipt만으로는 L2 실행 성공 여부를 알 수 없다. L2 실행 확인 방법:

- **Contract creation**: `eth_getCode(predictedAddress)` 폴링 → 코드가 나타나면 성공
- **Function call**: View function 호출로 상태 변경 확인

---

## 주의사항

- L1 Sepolia 가스비가 급등할 수 있음 → Admin 계정에 0.5+ ETH 유지
- Deposit Tx는 순차 실행 필수 (병렬 실행 시 nonce 예측 실패)
- 12개 트랜잭션 완료까지 약 5분 (Sepolia 기준)
