---
updated: 2026-04-27
component: trh-backend / thanos_stack.go
---

# BuildLocalChainInformation — L1ChainID is 0 (wrong rollup.json path)

## 증상

CrossTrade 자동 설치 시 다음 에러:

```
L1ChainID is 0: rollup.json may not be available yet
```

L2 배포가 완료되어 rollup.json 파일이 존재함에도 trh-backend가 chain ID를 읽지 못한다.

## 근본 원인

`trh-backend/pkg/stacks/thanos/thanos_stack.go`의 `BuildLocalChainInformation`이
잘못된 경로에서 rollup.json을 읽으려 한다:

```go
// 수정 전 — 존재하지 않는 경로
rollupPath := deploymentPath + "/tokamak-thanos/build/rollup.json"
```

`/tokamak-thanos/build/` 디렉토리는 배포 결과물에 존재하지 않는다.
실제 파일은 배포 루트 디렉토리 바로 아래에 있다:

```bash
# 실제 위치 확인
find $DEPLOYMENT_PATH -name "rollup.json"
# → $DEPLOYMENT_PATH/rollup.json
```

`os.ReadFile`이 실패해도 오류를 묵음 처리(`err == nil` 분기만 진입)하므로
`L1ChainID`와 `L2ChainID`가 0으로 남는다.

## 영향

- `BuildLocalChainInformation`이 반환하는 `ChainInformation.L1ChainID = 0`
- `deployment.go:710`: `if chainInfo.L1ChainID == 0 { return nil, fmt.Errorf(...) }` → CrossTrade 설치 차단
- `RollupFilePath`도 잘못된 경로를 가리켜 프런트엔드에 잘못된 값 제공

## 수정 (trh-backend commit `6786459`)

```go
// 수정 후
info := &thanosTypes.ChainInformation{
    // ...
    RollupFilePath: deploymentPath + "/rollup.json",  // was: /tokamak-thanos/build/rollup.json
}
rollupPath := deploymentPath + "/rollup.json"         // was: /tokamak-thanos/build/rollup.json
```

## 관련 문서

- [[drb-deposit-and-activate-threshold-mismatch]] — 같은 배포 세션에서 발견된 DRB 버그
