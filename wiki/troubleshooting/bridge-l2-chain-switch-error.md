---
updated: 2026-05-19
sources: []
related: []
tags: [troubleshooting]
---


# Bridge — "You can't automatically switch the chain in this app."

## 증상

Thanos Bridge 에서 MetaMask 를 통해 L2 네트워크를 추가/전환하려 하면:

> You can't automatically switch the chain in this app. Please try to add the network in your wallet manually.

## 근본 원인

`wallet_addEthereumChain` RPC 에 `blockExplorerUrls: [""]` (빈 문자열)을 전달하면 MetaMask 가 거부한다.

### 원인 1 — network.ts 버그 (항상 발생)

`thanos-bridge/src/config/network.ts` 의 `l2Chain.blockExplorers` 가 무조건 렌더링되었다:

```typescript
blockExplorers: {
  default: {
    name: env("NEXT_PUBLIC_L2_BLOCK_EXPLORER") || "Block Explorer", // name에 URL 값 사용 버그
    url: env("NEXT_PUBLIC_L2_BLOCK_EXPLORER") || "",  // 빈 문자열 → 거부
  },
},
```

`NEXT_PUBLIC_L2_BLOCK_EXPLORER` 가 없으면 `url: ""` → MetaMask 거부.

### 원인 2 — L2BlockExplorer 누락 (AWS 배포 시)

`trh-sdk/pkg/types/op_bridge_config.go` 에 `L2BlockExplorer` 필드가 없었다.
→ `op-bridge-values.yaml` 에 `l2_block_explorer: ""` 이 기록되지 않음
→ bridge ConfigMap 의 `NEXT_PUBLIC_L2_BLOCK_EXPLORER` 가 항상 빈 문자열

### 원인 3 — 배포 시점의 타이밍 (AWS 배포 시)

block-explorer 설치는 `installPresetModules()` 에서 bridge 설치 이후에 실행된다.
bridge `helm install` 시점에는 block-explorer ingress URL 이 아직 없으므로
`L2BlockExplorer=""` 로 설치된다.

## 수정 (2026-05-19)

### thanos-bridge `network.ts` (`9b5df75`)

URL 이 없을 때 `blockExplorers` 필드 자체를 생략:

```typescript
const l2BlockExplorerUrl = env("NEXT_PUBLIC_L2_BLOCK_EXPLORER") || "";

export const l2Chain: Chain = {
  // ...
  ...(l2BlockExplorerUrl
    ? {
        blockExplorers: {
          default: { name: "Block Explorer", url: l2BlockExplorerUrl },
        },
      }
    : {}),
};
```

### trh-sdk (`0177f33`)

1. `OpBridgeConfig.OpBridge.Env.L2BlockExplorer string` 필드 추가
2. `InstallBridge()` 에서 `t.deployConfig.BlockExplorerURL` 세팅 (deploy 시점은 빈 문자열)
3. `UpdateBridgeBlockExplorer(ctx, url)` 추가:
   - `op-bridge-values.yaml` 읽기 → L2BlockExplorer 패치 → 파일 쓰기
   - `FilterHelmReleases("op-bridge")` 로 기존 release 찾기
   - `helm upgrade <release> --values op-bridge-values.yaml` 실행
   - deployment.yaml 의 `checksum/config` 어노테이션이 ConfigMap 변경을 감지 → pod 자동 재시작

### trh-backend `deployment.go` (`dfba2e0`)

block-explorer URL sync 성공 블록에 `UpdateBridgeBlockExplorer` 호출 추가:

```go
} else {
    stackMeta.ExplorerUrl = beUrl
    if syncErr := s.stackRepo.UpdateMetadata(...); syncErr != nil { ... }
    if bridgeErr := thanos.UpdateBridgeBlockExplorer(ctx, sdkClient, beUrl); bridgeErr != nil {
        logger.Warn("failed to update bridge block explorer URL", ...)
    }
}
```

## 흐름 요약

1. AWS 배포 완료 → `markCompletedAndAutoInstall()` 진입
2. `resolveBlockExplorerURL()` 으로 block-explorer ingress URL (`beUrl`) 획득
3. integration row 를 `Completed` 로 마킹 + `stackMeta.ExplorerUrl = beUrl`
4. `UpdateBridgeBlockExplorer(ctx, sdkClient, beUrl)` → `helm upgrade` 실행
5. op-bridge ConfigMap 의 `NEXT_PUBLIC_L2_BLOCK_EXPLORER` = beUrl 로 갱신
6. pod 재시작 후 MetaMask `wallet_addEthereumChain` 이 정상 작동

## 기존 배포 복구

### API 엔드포인트 (권장)

이미 배포된 스택에서 block-explorer URL 이 stack metadata 에 저장되어 있다면
(`ExplorerUrl != ""`), 다음 API 호출로 즉시 bridge pod 을 업데이트할 수 있다:

```
POST /stacks/thanos/{stackId}/integrations/bridge/sync-block-explorer
```

내부 동작: `stackMeta.ExplorerUrl` 읽기 → `op-bridge-values.yaml` 패치 → `helm upgrade` → pod 재시작

### 자동 복구

trh-backend 이미지를 최신으로 업데이트하면 다음 `markCompletedAndAutoInstall` 호출 시
`UpdateBridgeBlockExplorer` 가 자동으로 실행된다.

### 수동 복구

1. `op-bridge-values.yaml` 에서 `l2_block_explorer` 를 실제 URL 로 업데이트
2. `helm upgrade <op-bridge-release> <chart-path> --values op-bridge-values.yaml -n <namespace>`

## 관련 파일

- `thanos-bridge/src/config/network.ts` — L2 chain wagmi 정의
- `trh-sdk/pkg/types/op_bridge_config.go` — OpBridgeConfig 구조체
- `trh-sdk/pkg/stacks/thanos/bridge.go` — InstallBridge, UpdateBridgeBlockExplorer
- `trh-backend/pkg/services/thanos/deployment.go` — markCompletedAndAutoInstall
- `tokamak-thanos-stack/charts/op-bridge/templates/deployment.yaml` — checksum 어노테이션
