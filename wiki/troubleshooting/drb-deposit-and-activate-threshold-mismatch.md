---

updated: 2026-05-19
sources: []
related:
  - "[[drb-deposit-and-activate-l2-not-ready]]"
  - "[[dispute-game-factory-no-implementations-pre-v006]]"
tags: [troubleshooting]
---
# DRB depositAndActivate — execution reverted (threshold mismatch)

## 증상

스택 배포 완료 후 DRB 오케스트레이션에서 실패:

```
failed to orchestrate DRB operators: activate regular operators:
  regular 1 depositAndActivate submission failed: execution reverted
```

L2가 이미 블록 > 0 상태임에도 (`waitForL2Ready` 통과 후) 실패하는 경우.

## 근본 원인

`tokamak-deployer`가 genesis.json 생성 시 CommitReveal2L2 프록시의 스토리지 슬롯 7에
`s_activationThreshold = 0x016345785d8a0000 = 100,000,000,000,000,000 wei = **0.1 ETH**`를 설정한다.

`trh-sdk`의 `patchGenesisWithDRB`는 **바이트코드만** 교체하고 스토리지를 건드리지 않으므로
genesis.json에 deployer가 설정한 0.1 ETH threshold가 그대로 보존된다.

반면 `local_network.go`에서는:

```go
// 수정 전 — local_network.go
threshold := DefaultDRBGenesisConfig().ActivationThreshold  // = big.NewInt(3) = 3 wei
ActivateRegularOperators(ctx, l2RPC, contractAddr, accounts, threshold)
```

`depositAndActivate()`의 Solidity 체크:

```solidity
require(msg.value == s_activationThreshold, "wrong value");
// msg.value = 3 wei ≠ s_activationThreshold = 0.1 ETH → revert
```

## 확인 방법

`cast call` 로 라이브 컨트랙트에서 threshold 확인:

```bash
cast call 0x4200000000000000000000000000000000000060 \
  "s_activationThreshold()(uint256)" \
  --rpc-url http://localhost:8545
# 결과: 100000000000000000 (0.1 ETH)
```

오류 발생 직전 로그에서 `waitForL2Ready` 통과 후 바로 revert가 나타나면 이 버그.

## 수정 (trh-sdk commit 7979644)

`ActivateRegularOperators`에서 `threshold *big.Int` 파라미터를 제거하고,
라이브 컨트랙트에서 직접 읽도록 변경:

```go
// 수정 후 — drb_activate.go
type activationThresholdReader interface {
    SActivationThreshold(opts *bind.CallOpts) (*big.Int, error)
}

func readActivationThreshold(_ context.Context, reader activationThresholdReader) (*big.Int, error) {
    threshold, err := reader.SActivationThreshold(nil)
    if err != nil {
        return nil, fmt.Errorf("read s_activationThreshold from contract: %w", err)
    }
    return threshold, nil
}

func ActivateRegularOperators(ctx context.Context, rpcURL string, contractAddr string, accounts *DRBAccounts) error {
    // ...
    threshold, err := readActivationThreshold(ctx, contract)
    // auth.Value = threshold → 항상 컨트랙트 실제 값과 일치
}
```

```go
// 수정 후 — local_network.go
// DefaultDRBGenesisConfig().ActivationThreshold 참조 제거
ActivateRegularOperators(ctx, l2RPC, contractAddr, accounts)  // threshold 파라미터 없음
```

## 관련 잠재적 버그

`patchGenesisWithDRBRegularFunding` (`drb_genesis.go:152`) 도 동일 클래스:
- `DefaultDRBGenesisConfig().ActivationThreshold = 3 wei`로 Regular 오퍼레이터 펀딩 계산
- `max(3 × 10, 1e18) = 1 ETH` 클램프로 현재는 안전 (실제 threshold 0.1 ETH 충분히 커버)
- threshold가 `1e17 wei (0.1 ETH)` 초과로 설정되면 Regular가 충분한 잔액 없이 시작될 수 있음

## 관련 문서

- [[drb-deposit-and-activate-l2-not-ready]] — 같은 증상의 다른 원인 (L2 genesis 상태)
- [[dispute-game-factory-no-implementations-pre-v006]] — 같은 배포 세션에서 발견된 다른 버그
