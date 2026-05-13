# forkchoiceUpdatedV3 post-Cancun 거부 → L2 block 0 stuck

**증상**: L2 체인이 block 0에서 멈춤. op-node 로그에 `"Unsupported fork"`, op-geth 로그에 `"forkchoiceUpdatedV3 must only be called for cancun payloads"`. op-proposer는 `"L2 safe/finalized head is at genesis (block 0)"` 반복.

## 근본 원인

`tokamak-thanos-geth/eth/catalyst/api.go`의 `ForkchoiceUpdatedV3` 핸들러가 다음 조건으로 블록을 거부:

```go
// 버그: == Cancun만 허용, 그보다 높은 포크(Prague/Isthmus)는 거부
if api.eth.BlockChain().Config().LatestFork(params.Timestamp) != forks.Cancun {
    return engine.STATUS_INVALID, engine.UnsupportedFork.With(...)
}
```

`tokamak-thanos` op-node는 Ecotone 이후 모든 블록에 `engine_forkchoiceUpdatedV3`를 사용한다 (`ForkchoiceUpdatedVersion` 참조). genesis에 `pragueTime = isthmusTime = genesis.timestamp`가 설정된 체인에서는 **모든 블록이 Prague 포크 이상**이므로 V3 요청이 항상 거부된다.

### 체인 설정 예시 (full-by6en)

```json
{
  "timestamp": "0x6a03b4e0",
  "config": {
    "cancunTime": 0,
    "pragueTime": 1778627808,   // == genesis timestamp
    "isthmusTime": 1778627808   // == genesis timestamp
  }
}
```

genesis 타임스탬프 = pragueTime = isthmusTime → 최초 블록부터 Prague 포크 → V3 항상 거부.

## 수정 (2026-05-13, tokamak-thanos-geth ff0caa15b)

```go
// 수정: Cancun 미만(pre-Cancun)만 거부, Cancun 이상은 모두 허용
if api.eth.BlockChain().Config().LatestFork(params.Timestamp) < forks.Cancun {
    return engine.STATUS_INVALID, engine.UnsupportedFork.With(
        errors.New("forkchoiceUpdatedV3 must only be called for cancun or later payloads"))
}
```

`< forks.Cancun`으로 변경하면 Cancun, Prague/Isthmus, Osaka, BPO* 등 미래 포크도 모두 V3에서 허용된다.

## 재시작 절차 (EKS)

체인데이터 초기화 없이 pod만 재시작하면 된다. genesis는 이미 정상 초기화되어 있고, op-geth가 새 이미지로 기동되면 op-node의 FCU V3 요청을 받아 block 1부터 생산 재개.

```bash
# imagePullPolicy: IfNotPresent이면 새 이미지를 강제 pull해야 함
kubectl patch statefulset <stack>-thanos-stack-op-geth -n <namespace> \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"op-geth","imagePullPolicy":"Always"}]}}}}'
kubectl rollout restart statefulset/<stack>-thanos-stack-op-geth -n <namespace>
kubectl rollout restart deployment/<stack>-thanos-stack-op-batcher -n <namespace>
```

## 관련 참고

- `NewPayloadV3`의 동일한 체크(line ~560)는 **올바름** — V3 payload는 Cancun 전용이 맞음. 변경 불필요.
- `NewPayloadV4`는 Isthmus를 이미 처리 중 (정상).
- op-node의 `ForkchoiceUpdatedVersion`은 IsEcotone 이상에서 V3를 보내므로, op-geth가 Cancun+을 모두 허용해야 한다.
