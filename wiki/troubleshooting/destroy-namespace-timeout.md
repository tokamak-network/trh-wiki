---
updated: 2026-05-06
sources:
  - trh-sdk/pkg/stacks/thanos/k8s.go
  - trh-sdk/pkg/stacks/thanos/destroy_chain.go
related:
  - "[[ec2-deploy]]"
  - "[[trh-sdk]]"
tags: [troubleshooting, destroy, kubernetes]
---

# Destroy Namespace Timeout — `context deadline exceeded` on `kubectl delete namespace`

AWS L2 stack을 Dashboard에서 Destroy할 때 정확히 5분 후 `❌ Failed to delete namespace ... context deadline exceeded` 로 멈추고 terraform destroy까지 못 가는 증상.

## 증상

trh-backend 로그:

```
INFO    Destroying infrastructure...
INFO    🧹 Cleaning up unused backup resources...      [OK, ~10s]
INFO    Uninstalling DRB / Bridge / BlockExplorer / Monitoring / UptimeService [OK]
INFO    Uninstalling Helm release: <chain>-<ts> in namespace: <namespace>...
INFO    Helm release removed successfully
                                                       ← 여기서 정확히 5분 hang
ERROR   ❌ Failed to delete namespace namespace=<namespace> err=context deadline exceeded
ERROR   failed to destroy infrastructure
INFO    Task completed
```

DB: stack `Terminating` 또는 `FailedToTerminate`. AWS: 백업 vault, optional Helm release는 정리됐으나 EKS 클러스터·VPC·ALB·EFS는 그대로.

## 근본 원인 (수정 전)

`trh-sdk/pkg/stacks/thanos/destroy_chain.go` `destroyInfraOnAWS()` 와
`trh-sdk/pkg/stacks/thanos/k8s.go` `tryToDeleteK8sNamespace()` 의 3개 결함이 결합:

### 1. `kubectl delete namespace`가 동기 + finalizer 자가복구 없음

```go
// 수정 전 k8s.go
kubectl delete namespace <ns>   // finalizer 모두 풀릴 때까지 동기 대기
```

namespace 안에 finalizer 보유한 자원이 있으면 (보통 LoadBalancer Service의 `service.kubernetes.io/load-balancer-cleanup`, EFS-CSI PV의 `kubernetes.io/pv-protection`) 5분 timeout까지 진행이 안 됨. phase가 `Active`로 시작하므로 코드의 finalizer 강제 클리어 분기(`status.Phase == "Terminating"`)도 첫 호출에는 안 탐.

### 2. EFS Mount Target 정리가 namespace 삭제 *후*

```go
// 수정 전 destroy_chain.go (L124-145)
1. tryToDeleteK8sNamespace(...)         ← 5min hang, fatal return
2. backup.DeleteEFSMountTargets(...)    ← 도달하지 못함
```

EFS PV의 finalizer는 EFS-CSI controller가 mount unbind 후 풀어주는데, mount target이 살아있으면 unbind가 늦어짐. 정리 순서가 거꾸로.

### 3. namespace 실패 = 전체 destroy 실패

```go
if err := t.tryToDeleteK8sNamespace(...); err != nil {
    return err     // ← terraform destroy까지 도달 못함
}
```

terraform destroy가 EKS 클러스터를 통째로 지우면 namespace는 자동 소멸하는데, 그 마지막 안전망에 도달조차 못 함.

### 4. (잠재) `K8sNamespaceStatus.Status.Conditions` 가 `string` 타입

실제 Terminating namespace JSON은 `status.conditions`가 array. force-finalize 코드 경로가 도달해도 `json.Unmarshal` 단계에서 실패. 자가복구 코드가 사실상 작동 안 했음.

## 수정 (trh-sdk `4099570`, 2026-05-06)

`fix(destroy): self-heal stuck namespace and reorder EFS cleanup before namespace delete`

### `destroy_chain.go`
- EFS mount target 삭제를 namespace 삭제 *앞*으로 이동 — `DetectEFSId`가 PVC 읽으므로 namespace 살아있을 때 호출되어야 + EFS PV finalizer 조기 해제
- namespace 삭제 실패 → `return err`를 `warn-and-continue`로 강등 → terraform destroy까지 흐름 보장

### `k8s.go` `tryToDeleteK8sNamespace` 자가복구 5단계
1. `kubectl delete namespace <ns> --wait=false` (비차단, phase를 Terminating으로 전환)
2. polling으로 phase=`Terminating` 확인 (또는 namespace 소멸) — 30초 deadline
3. **stuck finalizer 강제 클리어** (best-effort):
   - 해당 namespace의 모든 Service `metadata.finalizers=null` patch
   - 해당 namespace의 모든 PVC `metadata.finalizers=null` patch
   - claimRef.namespace가 일치하는 cluster-scoped PV `metadata.finalizers=null` patch
4. namespace 자체 finalizer 강제 클리어: `kubectl replace --raw /api/v1/namespaces/<ns>/finalize`
5. ctx deadline까지 polling으로 namespace 소멸 확인

### 추가 안정화
- generic `map[string]interface{}` 로 finalize body 빌드 → status.conditions array 등 unknown 필드 round-trip
- `os.CreateTemp` → 동시 destroy race 방지 (이전엔 `/tmp/namespace.json` 하드코딩)
- ctx deadline 없을 때 5분 safety-net 자동 적용 → `uptime_service.go:281` 경로 무한 대기 방지

### Unit test
- `buildNamespaceFinalizeBody` 5 케이스 (real Terminating-with-conditions 포함)
- `extractNamespacePhase` 4 케이스
- `_PreservesIdentity` apiVersion/kind/metadata 보존 보증

## Stuck Stack 수동 정리 절차

수정 전 버전으로 destroy 시도해서 잔존 자원이 있을 때:

### 1. EKS 클러스터에 접속

```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

### 2. 무엇이 finalizer를 잡고 있는지 확인

```bash
kubectl get ns <namespace> -o yaml | grep -A5 finalizers
kubectl get all,pvc -n <namespace>
kubectl get pv | grep <namespace>
kubectl get svc -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.finalizers}{"\n"}{end}'
```

흔한 보유자: `service.kubernetes.io/load-balancer-cleanup` 가 매달린 LB Service, `kubernetes.io/pv-protection` 가 매달린 EFS PV.

### 3. finalizer 강제 제거

```bash
# Service finalizer
kubectl patch svc <name> -n <namespace> --type=merge -p '{"metadata":{"finalizers":null}}'

# PVC finalizer
kubectl patch pvc <name> -n <namespace> --type=merge -p '{"metadata":{"finalizers":null}}'

# PV finalizer
kubectl patch pv <name> --type=merge -p '{"metadata":{"finalizers":null}}'

# Namespace 자체 finalizer
kubectl get ns <namespace> -o json \
  | jq '.spec.finalizers = []' \
  > /tmp/ns.json
kubectl replace --raw "/api/v1/namespaces/<namespace>/finalize" -f /tmp/ns.json
```

### 4. EFS Mount Target 직접 삭제 (terraform destroy 전 필수)

```bash
EFS_ID=$(aws efs describe-file-systems --region <region> --query "FileSystems[?Tags[?Value=='<chain-name>']].FileSystemId" --output text)
for MT in $(aws efs describe-mount-targets --region <region> --file-system-id $EFS_ID --query 'MountTargets[].MountTargetId' --output text); do
  aws efs delete-mount-target --region <region> --mount-target-id $MT
done
```

### 5. terraform destroy

```bash
cd <deploymentPath>/tokamak-thanos-stack/terraform/thanos-stack
source ../.envrc
terraform destroy -auto-approve -parallelism=1

cd ../backend
source ../.envrc
terraform destroy -auto-approve -parallelism=1
```

### 6. trh-backend DB 정합성 회복

수정 전 코드는 destroy 도중 실패해도 `FailedToTerminate`로 마킹만 함. 수동 정리 후에는 DB의 stack 상태를 강제로 `Terminated`로 바꿔야 Dashboard에 잘못 표시되지 않음 (별도 SQL 또는 backend 재기동 후 status 수정 API).

## 관련 문서

- [[ec2-deploy]] — AWS L2 배포 전체 플로우 (Teardown 섹션)
- [[trh-sdk]] — SDK 컴포넌트 개요
