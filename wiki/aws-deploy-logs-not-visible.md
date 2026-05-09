---
updated: 2026-05-09
---

# AWS 인프라 배포 실시간 로그 미표시

## 증상

DeploymentsTab에서 `deploy-aws-infra` 배포 행의 **Logs** 버튼을 클릭하면  
LogDialog에 "No logs available" 또는 빈 목록이 표시된다.  
같은 배포에서 `deploy-l1-contracts`의 로그는 정상 표시된다.

## 근본 원인

`executeDeploymentsAWSParallel` (`trh-backend/pkg/services/thanos/deployment.go`)이  
**단일 공유 SDK 클라이언트**를 생성하면서 `l1Step.LogPath`만 전달한다.

```go
// SDK 내부 logger → l1Step.LogPath 기록
sdkClient, _ = thanos.NewThanosSDKClient(ctx, l1Step.LogPath, ...)

// 바이너리 subprocess 출력 → l1Step.LogPath 기록
logFile, _ := os.OpenFile(l1Step.LogPath, ...)
sdkClient.SetOutput(io.MultiWriter(os.Stdout, logFile))

// awsStep용 goroutine은 존재하지 않는 파일을 기다림
go s.tailAndIngestDeploymentLogs(awsIngestCtx, stack.ID, awsStep.ID, awsStep.LogPath) // ← 버그
```

`tailAndIngestDeploymentLogs`는 파일이 생길 때까지 500ms 간격으로 폴링한다.  
`awsStep.LogPath` 파일은 절대 생성되지 않으므로 goroutine은 영구 블로킹 →  
DB에 AWS step 로그 0건 → UI "No logs available".

### 로그 경로 생성 방식

```go
// internal/utils/deployment.go
func GetLogPath(stackID uuid.UUID, plugin string) string {
    return path.Join(rootDir, "storage", "logs", stackID.String(),
        timestamp + fmt.Sprintf("_%s_logs.txt", plugin))
}
// 예: storage/logs/{id}/2026-05-09-12-00-00_deploy-aws-infra_logs.txt
```

`l1Step.LogPath`와 `awsStep.LogPath`는 `plugin` 부분이 달라 **다른 경로**가 된다.  
SDK 클라이언트는 `l1Step.LogPath`에만 쓰므로 `awsStep.LogPath`는 절대 생성되지 않는다.

## 수정

단일 SDK 클라이언트가 모든 출력(L1 + AWS)을 하나의 파일에 쓰는 구조를 반영해,  
AWS ingestion goroutine도 동일한 공유 파일을 읽도록 변경한다.

```go
// 수정 전
go s.tailAndIngestDeploymentLogs(awsIngestCtx, stack.ID, awsStep.ID, awsStep.LogPath)

// 수정 후 — awsStep shares the same SDK client and log file as l1Step; read from the shared path
go s.tailAndIngestDeploymentLogs(awsIngestCtx, stack.ID, awsStep.ID, l1Step.LogPath)
```

결과: AWS 배포 LogDialog를 열면 L1 + AWS 전체 로그(두 단계 출력 혼합)가 실시간으로 표시된다.

- **trh-backend 커밋**: `958d898`

## 주의사항

- AWS 배포 LogDialog는 L1 로그도 함께 보여준다 (단일 파일이므로 의도된 동작).
- 두 goroutine이 같은 파일을 독립적으로 폴링하여 각자 DB에 삽입하므로  
  같은 로그 라인이 `l1Step.ID`와 `awsStep.ID` 두 deployment에 각각 저장된다.
- 이는 중복 저장이지만 각 다이얼로그가 독립 조회(`deploymentId` 기준)하므로 기능 동작에 문제 없다.
