# Stage B: Backend configuration changed

**Symptom**: AWS L2 배포 Stage B에서 `terraform init`이 즉시 실패.

```
Error: Backend configuration changed

A change in the backend configuration has been detected, which may require
migrating existing state.
...
ERROR: AWS Stage B failed
ERROR: failed to deploy thanos stacks
```

Stage A (75 AWS 리소스), L1 컨트랙트 배포, forge L2Genesis는 모두 성공한 후 Stage B 진입 시 발생.

---

## 근본 원인 (두 가지, trh-sdk 1f58eee에서 수정)

### 원인 1 — 랜덤 namespace 재생성

`deploy_chain.go`의 Stage B 진입부가 `utils.ConvertChainNameToNamespace(inputs.ChainName)`를 다시 호출했다. 이 함수는 매 호출마다 `rand.Read`로 새 5자리 suffix를 생성한다 (`full` → `full-eu5up` → `full-w8ygx`). Stage A와 다른 namespace가 만들어지면 `SwitchKubernetesContext`, `CheckK8sReady`, `helmReleaseName` 등에 잘못된 값이 전달된다.

### 원인 2 — 빈 backend bucket name으로 .envrc 덮어쓰기

`makeTerraformEnvFile`이 `TF_VAR_backend_bucket_name`에 하드코딩된 `""`를 써넣었다. Stage B는 `.envrc`를 완전히 덮어쓰기 때문에 `bucket_name.sh`가 Stage A에서 채워 놓은 버킷 이름이 사라졌다. `terraform init`은 backend hash를 `bucket=` (빈 값)으로 계산하여 Stage A가 저장한 `bucket=full-eu5up-thanos-stack-tfstate-flea1wn6`와 충돌했다.

---

## 수정 내용

Stage B는 이제 `thanos-stack/.terraform/terraform.tfstate`(Stage A의 `terraform init`이 작성한 로컬 working-directory 파일)를 읽어 namespace와 bucket을 복원한다:

```go
// deploy_chain.go — Stage B 진입부
namespace, backendBucketName, err := readBackendStateFromTfstate(terraformDir)
```

`readBackendStateFromTfstate` 헬퍼(`input.go`):
- `.terraform/terraform.tfstate`의 `backend.config.bucket` 필드 파싱
- `{namespace}-thanos-stack-tfstate-{random}` 형식에서 namespace 추출
- bucket이 비어 있거나 포맷이 다르면 명시적 에러 반환

---

## `.terraform/` 디렉토리를 삭제한 경우

사용자가 `.terraform/` 디렉토리를 수동으로 삭제하면 Stage B가 다음 에러로 실패한다:

```
Stage B requires Stage A terraform state: read terraform backend state: open .../thanos-stack/.terraform/terraform.tfstate: no such file or directory
```

### 복구 방법

Stage A를 다시 실행하거나, 수동으로 `terraform init`을 실행한다:

```bash
cd {deploymentPath}/tokamak-thanos-stack/terraform/thanos-stack
# .envrc에서 TF_VAR_backend_bucket_name이 올바르게 설정되어 있어야 함
direnv allow
terraform init
```

`TF_VAR_backend_bucket_name`은 S3에서 기존 bucket 이름을 확인하여 수동으로 설정해야 한다.

---

## 관련

- [[destroy-namespace-timeout]] — AWS destroy 후 재배포 시 namespace 불일치 패턴
- `trh-sdk` commit `1f58eee` — 수정 커밋
