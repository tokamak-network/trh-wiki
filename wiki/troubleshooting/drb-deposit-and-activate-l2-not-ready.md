---

updated: 2026-05-19
sources: []
related:
  - "[[dispute-game-factory-no-implementations-pre-v006]]"
  - "[[op-node-genesis-l1-block-zero]]"
tags: [troubleshooting]
---
# DRB depositAndActivate — execution reverted (L2 at genesis)

## 증상

스택 배포 완료 직후 DRB 오케스트레이션에서 실패:

```
failed to orchestrate DRB operators: activate regular operators:
  regular 1 depositAndActivate submission failed: execution reverted
```

로그 타임라인을 보면 DRB 컨테이너 재시작 후 정확히 5초 뒤 실패:

```
02:47:13  ⏳ Waiting for DRB containers to stabilize...
02:47:18  📡 Activating Regular DRB operators on-chain...
02:47:18  ERROR: regular 1 depositAndActivate submission failed: execution reverted
```

## 근본 원인

`orchestrateDRBOperators`의 `time.After(5 * time.Second)` 대기가 너무 짧다.

DRB 컨테이너가 재시작될 때 L2는 아직 genesis 상태(block 0)에 있을 수 있다.
op-geth + op-node가 기동되고 첫 L2 블록을 시퀀싱하기까지 5초 이상 걸릴 수 있으며,
block 0에서 `depositAndActivate`의 `eth_estimateGas` 시뮬레이션이 revert된다.

**확인 방법**: 오류 발생 직전 `⏳ Waiting for DRB containers to stabilize...` 로그와
`📡 Activating Regular DRB operators on-chain...` 사이의 시간이 정확히 5초이면 이 버그.

## 수정 (trh-sdk commit 034364c)

`waitForL2Ready()` 함수 추가:
- `eth_blockNumber`를 2초 간격으로 폴링
- block > 0이 되면 통과 (L2가 시퀀싱 중임을 확인)
- 타임아웃: 2분

5초 고정 sleep을 `waitForL2Ready()` 호출로 교체.

```go
// 수정 전
select {
case <-time.After(5 * time.Second):
case <-ctx.Done():
    return ctx.Err()
}

// 수정 후
if err := waitForL2Ready(ctx, l2RPC, t.logger); err != nil {
    return fmt.Errorf("L2 not ready after timeout: %w", err)
}
```

## 관련 문서

- [[dispute-game-factory-no-implementations-pre-v006]] — 같은 배포 세션에서 발견된 Bug #8
- [[op-node-genesis-l1-block-zero]] — 함께 나타날 수 있는 SystemConfig.startBlock() 미초기화 문제
