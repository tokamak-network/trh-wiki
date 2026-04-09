---
updated: 2026-04-09
sources:
  - raw/architecture/local-l2-deployment-test-guide.md
related:
  - "[[l2-deploy-local]]"
  - "[[deposit-tx]]"
  - "[[trh-sdk]]"
tags: [troubleshooting]
---

# L1 Gas Limits

L1 컨트랙트 배포 또는 Deposit Transaction 실행 시 가스 한도 관련 실패.

---

## 알려진 가스 한도 값

| 오퍼레이션 | L1 가스 | L2 가스 (depositTransaction 내) |
|-----------|--------|-------------------------------|
| depositTransaction (contract creation) | ~100k–150k | 3,000,000 |
| depositTransaction (function call) | ~60k–80k | 500,000 |
| setSelectorImplementations2 | ~60k–80k | 1,000,000 (증가됨) |
| initialize | ~60k–80k | 1,000,000 (증가됨) |
| L1 setChainInfo (직접 호출) | ~80k–120k | N/A |

`setSelectorImplementations2`와 `initialize`의 L2 가스 한도는 초기 500K에서 1M으로 상향 조정됐다. (commit: `a99e486` 근처)

---

## 증상

```
Error: transaction failed
Error: gas limit too low
Error: out of gas
```

---

## 해결

`trh-sdk/pkg/stacks/thanos/cross_trade_local.go`에서 해당 단계의 `gasLimit` 값을 증가시킨다.

```go
// depositTransaction 호출 시
gasLimit := big.NewInt(1_000_000) // 500_000 → 1_000_000
```

---

## 주의

Sepolia 네트워크 상태에 따라 L1 가스 가격이 급등할 수 있다. 계정에 충분한 ETH를 유지해야 한다 (Admin: 0.5+ ETH).
