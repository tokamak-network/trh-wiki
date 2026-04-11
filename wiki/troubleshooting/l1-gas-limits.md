---
updated: 2026-04-11
sources:
  - raw/architecture/local-l2-deployment-test-guide.md
related:
  - "[[l2-deploy-local]]"
  - "[[deposit-tx]]"
  - "[[trh-sdk]]"
  - "[[cross-trade]]"
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
| L1 CrossTrade provideCT (L1→L2) | auto (ethers.js 추정) | N/A |
| L1 CrossTrade provideCT (L2→L2) | auto (ethers.js 추정) | ~800,000 (CDM 2회) |

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

---

## CrossTrade provideCT — explicit gasLimit 제거 배경

(commit: `8ec40d8`, 2026-04-11)

초기 구현에서는 L1 `provideCT` 호출에 explicit gasLimit을 지정했다. 이것이 문제였던 이유:

- L1→L2 `provideCT`는 OptimismPortal을 통해 L2에 cross-domain message를 전달한다. L2 실행 가스는 `_minGasLimit` 파라미터로 따로 제어되므로, L1 측 gasLimit을 낮게 고정하면 **OptimismPortal intrinsic gas accounting 실패**로 TX 자체가 revert될 수 있다.
- L2→L2 `provideCT`는 cross-domain message가 **2회** 발생한다 (L2→L1→L2). 이 경우 L1 TX가 두 메시지의 overhead를 모두 처리해야 하므로 같은 고정값으로는 insufficient.

**현재 정책:** ethers.js `provider.estimateGas()` 자동 추정에 맡긴다. E2E 테스트(`crosstrade-tx.live.spec.ts`)에서 gasLimit 미지정으로 검증 완료.

**L2-L2 minGasLimit:** `_minGasLimit` 파라미터는 `200_000` 고정 유지 (CDM 메시지 relay용, L1 TX gasLimit과 별개).

---

## 주의

Sepolia 네트워크 상태에 따라 L1 가스 가격이 급등할 수 있다. 계정에 충분한 ETH를 유지해야 한다 (Admin: 0.5+ ETH).
