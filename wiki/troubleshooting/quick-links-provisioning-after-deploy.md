---
updated: 2026-05-19
---

# Quick Links — "Provisioning…" after AWS deployment completes

## 증상

AWS Full/DeFi 프리셋 배포 완료 후에도 Quick Links 패널에서
**Block Explorer** 또는 **Uptime Service** 항목이 "Provisioning…" 으로 남는다.

`stacks.metadata` 컬럼의 `ExplorerUrl` 또는 `UptimeServiceUrl` 필드가 빈 문자열로 남기 때문.
`QuickLinks.tsx`는 이 필드가 falsy 이면 "Provisioning…" 을 표시한다.

## 근본 원인 (두 가지)

### 1. Block Explorer — integration record만 갱신, stackMeta 미갱신

`deployment.go` `markCompletedAndAutoInstall()`에서 `resolveBlockExplorerURL()` 폴백으로
block-explorer URL 을 획득하면, `integrationRepo.UpdateMetadataAfterInstalled()` 로
integration record 의 `info.url` 만 갱신했다.

`stacks.metadata` 의 `ExplorerUrl` 필드는 기존 빈 문자열 그대로 → Quick Links 미갱신.

### 2. Uptime Service — 30분 goroutine이 stale 스냅샷으로 덮어쓰기

`installTask` goroutine 은 launch 시점에 `stack` 변수를 클로저로 캡처한다.
goroutine 이 ~30분 후 완료 시, 캡처된 `stack.Metadata` 스냅샷(launch 시점 상태)으로
`UpdateMetadata` 를 호출하면:

- `ExplorerUrl` 이 ""(빈 문자열, launch 시점 값)로 덮어씌워짐
- 그 사이 deployment.go 가 설정한 `ExplorerUrl` 손실

추가로, launch 시점에 `stack.Metadata == nil` 이면 `UptimeServiceUrl` 업데이트 자체가
조용히 스킵 → `UptimeServiceUrl` 영구 누락.

## 수정 (trh-backend `4393632`)

### deployment.go

`UpdateMetadataAfterInstalled` 성공 후 `stackMeta.ExplorerUrl` 도 동기화:

```go
} else {
    stackMeta.ExplorerUrl = beUrl
    if syncErr := s.stackRepo.UpdateMetadata(stackId.String(), stackMeta); syncErr != nil {
        logger.Warn("failed to sync block-explorer URL to stack metadata", ...)
    }
}
```

### uptime_service.go

goroutine 완료 시점에 DB 에서 최신 metadata 를 re-fetch 한 뒤 `UptimeServiceUrl` 을 쓴다:

```go
var meta *entities.StackMetadata
if freshStack, fetchErr := u.stackRepo.GetStackByID(stack.ID.String()); fetchErr == nil && freshStack != nil && freshStack.Metadata != nil {
    meta = freshStack.Metadata
} else if stack.Metadata != nil {
    meta = stack.Metadata
}
if meta == nil {
    logger.Warn("no stack metadata available; skipping UptimeServiceUrl update", ...)
} else {
    meta.UptimeServiceUrl = uptimeServiceUrl
    u.stackRepo.UpdateMetadata(stack.ID.String(), meta)
}
```

- nil pointer guard (`var meta *entities.StackMetadata`) 사용 — `&entities.StackMetadata{}` 로 초기화하면 re-fetch 실패 + 캡처 스냅샷도 nil 인 경우 빈 struct 를 써서 다른 필드(`Layer1`, `L2RpcUrl` 등)를 날림.

## 알려진 한계

동일한 stale-snapshot 패턴이 `bridge.go`, `monitoring.go`, `block_explorer.go` 에도
존재하지만 실행 시간이 짧고(사용자 트리거 설치) 레이스 윈도우가 좁아 실제 문제가
될 가능성이 낮다. 별도 작업으로 처리 예정.

## 기존 배포 복구 (stuck Provisioning)

위 수정 이전에 배포된 스택에서 Quick Links 가 계속 "Provisioning…" 으로 보인다면:

```bash
# block-explorer
curl -X POST http://localhost:8000/api/v1/stacks/{stackId}/integrations/block-explorer \
  -H 'Content-Type: application/json' \
  -d '{"databaseUsername":"blockscout","databasePassword":"...","coinmarketcapKey":"...","coinmarketcapTokenId":"...","walletConnectId":"..."}'
```

SDK 가 pod 이 이미 존재하면 helm install 을 건너뛰고 URL 만 반환 + DB 갱신.

Uptime Service 의 경우 재설치 API 가 없으므로 DB 직접 패치가 필요하다 (별도 복구 방법 문서화 예정).

## 관련 파일

- `trh-backend/pkg/services/thanos/deployment.go` — `markCompletedAndAutoInstall` (block-explorer 동기화)
- `trh-backend/pkg/services/thanos/integrations/uptime_service.go` — `installTask` (re-fetch + nil guard)
- `trh-platform-ui` → `QuickLinks.tsx` — `stack.metadata.*` 로 URL 읽기
