---
updated: 2026-05-04
---

# SetKubeconfigFile / SetAWSConfigFile env path reuse bug

## 증상

단일 trh-backend 프로세스에서 두 번째 AWS 배포를 시작하면 kubeconfig가 corrupt되어 `YamlError while loading kubeconfig: line 30` 에러 발생.

## 근본 원인

`trh-sdk/pkg/utils/aws.go`의 세 함수가 `os.Getenv`로 환경변수가 이미 설정됐는지만 확인하고, **basePath가 다른 배포를 가리키는지 확인하지 않았다**:

```go
// 수정 전 (버그)
if existing := os.Getenv("KUBECONFIG"); existing != "" {
    return existing, nil  // 1차 배포 경로를 그대로 반환
}
```

결과: 2차 배포가 1차 배포의 kubeconfig 파일에 자신의 EKS 클러스터 정보를 추가 → 두 YAML document가 하나의 파일에 concat → parse 실패.

## 트리거 조건

- trh-backend 컨테이너 재시작 없이 두 번째 AWS 배포 시작
- 영향받는 함수: `SetKubeconfigFile`, `SetAWSConfigFile`, `SetAWSCredentialsFile`

## 수정 (trh-sdk 3f50d14)

```go
// 수정 후
kubePath := filepath.Join(basePath, ".kube", "config")
if existing := os.Getenv("KUBECONFIG"); existing == kubePath {
    return kubePath, nil  // basePath가 일치할 때만 skip
}
// 다른 경로면 항상 새로 설정
```

basePath가 달라지면 환경변수를 새 경로로 덮어쓴다.

## 커밋

- `trh-sdk feat/integrate-drb 3f50d14`
- `trh-backend main 62b56ea`
