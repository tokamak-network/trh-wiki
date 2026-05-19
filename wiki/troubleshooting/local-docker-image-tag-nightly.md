---
title: local docker image tag — thanos stack uses nightly
created: 2026-05-14
type: troubleshooting
---

# Local Docker Image Tag: thanos stack uses nightly

## 증상

로컬 L2 배포 Step 3/10 (Starting core services) 에서 실패:

```
✘ op-challenger Error: failed to resolve reference
  "docker.io/tokamaknetwork/thanos-op-challenger:af052710": not found
✘ op-node Error: context canceled
✘ op-batcher Error: context canceled
✘ op-proposer Error: context canceled
Command execution failed: exit status 18
```

## 근본 원인

`trh-sdk/pkg/constants/docker_images.go`의 `ThanosStackImageTag`는 짧은 커밋 해시(`af052710`)를 값으로 갖는다.

이 값을 사용하는 경로가 두 가지인데 태그 생성 방식이 달랐다:

| 경로 | 태그 생성 방식 | 결과 | 존재 여부 |
|------|-------------|------|---------|
| AWS EKS Helm 스크립트 | `nightly-` + ThanosStackImageTag | `nightly-af052710` | ✅ |
| 로컬 Docker Compose (`local_network.go`) | ThanosStackImageTag 직접 사용 | `af052710` | ❌ |

Docker Hub에는 `nightly-{commit}` 형식만 존재하고, 짧은 커밋 해시 단독 태그는 없다.

## 해결

`local_network.go`에서 thanos stack 이미지(op-node, op-batcher, op-proposer, op-challenger)를 `nightly` floating tag로 통일.

커밋 해시마다 업데이트가 필요 없고, Docker Hub의 최신 nightly 이미지를 항상 사용한다.

```go
// 수정 전
OpNodeImage: fmt.Sprintf("tokamaknetwork/thanos-op-node:%s", imageTags.ThanosStackImageTag),

// 수정 후
OpNodeImage: "tokamaknetwork/thanos-op-node:nightly",
```

**수정 파일**: `trh-sdk/pkg/stacks/thanos/local_network.go`  
**수정 커밋**: `f6f1df6`

## 주의

- `ThanosStackImageTag`는 AWS EKS Helm 스크립트에서 여전히 사용되므로 `docker_images.go`는 변경하지 않아도 된다.
- `OpGethImage`(`thanos-op-geth`)는 별도의 `OpGethImageTag: "nightly"`를 사용하므로 영향 없음.
