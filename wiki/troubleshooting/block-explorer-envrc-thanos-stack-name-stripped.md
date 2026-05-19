---
updated: 2026-05-06
related:
  - "[[block-explorer-update-pattern]]"
  - "[[crosstrade-aws-install-hang]]"
tags: [troubleshooting, aws, block-explorer, terraform]
sources: []
---


# Block Explorer .envrc 재작성으로 `TF_VAR_thanos_stack_name` 누락 → terraform plan stdin hang

## 증상

AWS 배포 중 chain 본배포 + DRB + AA Paymaster 까지 정상 진행 후
**block-explorer 통합 설치** 진입 시점에서 deployment 가 `InProgress` 상태로
정확히 머무름. trh-backend 로그/DB 에 진척 없음, 4 시간 이상 hang.

마지막 로그가 정확히 다음 형태로 끝남(터미널 ANSI 포함):

```
[1mvar.thanos_stack_name[0m
  Thanos stack name
```

→ Terraform 이 unset required variable 에 대해 stdin 으로 묻는 인터랙티브
프롬프트 형식.

trh-backend 컨테이너 안에서:

```
ps -ef
... bash -c "... cd block-explorer && terraform init && terraform plan && terraform apply -auto-approve"
... terraform plan          ← State: S (sleeping on stdin)
```

## 근본 원인

`trh-sdk/pkg/stacks/thanos/input.go` 의 `makeBlockExplorerEnvs` 가 .envrc 를
재작성할 때 다음 prefix 라인을 모두 제거(strip)한 뒤 새 값으로 다시 씀:

```go
dbVarPrefixes := []string{
    "export TF_VAR_db_username=",
    "export TF_VAR_db_password=",
    "export TF_VAR_db_name=",
    "export TF_VAR_vpc_id=",
    "export TF_VAR_aws_region=",
    "export TF_VAR_thanos_stack_name=",   // ← 항상 strip
}
...
if config.StackName != "" {                  // ← 비었으면 재추가 스킵
    lines = append(lines, fmt.Sprintf("export TF_VAR_thanos_stack_name=\"%s\"", config.StackName))
}
```

두 호출자 모두 `StackName` 필드를 채우지 않은 채 호출:

| 위치 | 함수 |
|------|------|
| `pkg/stacks/thanos/block_explorer.go:67` | `InstallBlockExplorer` |
| `pkg/stacks/thanos/block_explorer.go:340` | `UpdateBlockExplorer` |

→ `.envrc` 가 thanos_stack_name 라인 없이 다시 씌워짐.
→ 같은 .envrc 안에 `export TF_VAR_vpc_name="${TF_VAR_thanos_stack_name}/VPC"` 가
   남아 있어 source 시점에 `vpc_name` 이 `/VPC` 로 평가됨.
→ `block-explorer/variables.tf` 의 `variable "thanos_stack_name"` 은
   default 없는 required → terraform plan 이 변수 미설정 감지.
→ trh-sdk 가 호출하는 bash 명령이 `terraform plan` 을 **`-input=false` 없이**
   실행 → fail-fast 대신 stdin 으로 폴백.
→ 컨테이너에 응답할 TTY 없음 → 무한 대기.
→ 자식 프로세스가 살아 있을 뿐 DB 갱신만 멈춰서 backend orchestrator 도
   timeout 처리하지 않음.

## 수정 (trh-sdk f6f2f92, 2026-05-06)

Two-pronged:

### Caller fix (correctness)

`block_explorer.go:67,340` 두 호출 모두 `StackName: namespace` 명시.
`namespace = t.deployConfig.K8s.Namespace` 가 thanos_stack_name 과 동일한 값.

```go
types.AwsDatabaseEnvs{
    ...
    AwsRegion: t.deployConfig.AWS.Region,
    StackName: namespace,           // ← 추가
}
```

### Function-level safety (defensive)

`makeBlockExplorerEnvs` 가 caller 가 빈 `StackName` 을 넘겨도 기존 .envrc 의
값을 파싱·복원해서 다시 씀:

```go
stackName := config.StackName
...
for _, line := range strings.Split(string(content), "\n") {
    if stackName == "" && strings.HasPrefix(line, "export TF_VAR_thanos_stack_name=") {
        stackName = strings.Trim(strings.TrimPrefix(line, "export TF_VAR_thanos_stack_name="), `"`)
    }
    ...
}
...
if stackName != "" {
    lines = append(lines, fmt.Sprintf("export TF_VAR_thanos_stack_name=\"%s\"", stackName))
}
```

미래의 신규 caller 가 동일한 실수를 해도 회귀하지 않게.

### 단위 테스트

`block_explorer_envrc_test.go` 두 케이스:

1. caller 가 `StackName: "my-stack"` 명시 → .envrc 에 export 라인 존재
2. caller 가 빈 StackName 으로 호출 → 기존 .envrc 의 값 보존

수정 전에 2번이 fail, 수정 후 둘 다 pass.

## 즉시 복구 절차

수정은 신규 배포에만 효과. 이미 hang 된 배포는 자가 회복하지 않음 — backend
는 자식 프로세스 sleep 을 timeout 으로 인식할 신호가 없음.

```bash
# 1. trh-backend 컨테이너 안에서 hang 된 terraform 종료
docker exec trh-backend bash -c 'pkill -f "terraform plan"; pkill -f "block-explorer"'

# 2. 종료 시 bash 래퍼가 non-zero exit → SDK 가 deployment 를 Failed 로 전이
# 3. UI 에서 재배포 (수정된 SDK 빌드 필요)
```

## 후속 디펜스 적용 (trh-sdk 5071a36, 2026-05-06)

같은 부류의 stdin hang 을 미래에 차단하기 위해 `block_explorer.go`
와 `deploy_chain.go` 의 모든 `terraform init/plan/apply` 호출에
`-input=false` 를 일괄 추가:

```diff
- terraform init &&
- terraform plan &&
- terraform apply -auto-approve
+ terraform init -input=false &&
+ terraform plan -input=false &&
+ terraform apply -input=false -auto-approve
```

적용 위치:

| 파일 | 함수 | 모듈 |
|------|------|------|
| `block_explorer.go:101-103` | `InstallBlockExplorer` | block-explorer |
| `block_explorer.go:373` | `UpdateBlockExplorer` | block-explorer (init만, output 전) |
| `deploy_chain.go:328-330` | `deployNetworkToAWS` | backend (state 백엔드 부트스트랩) |
| `deploy_chain.go:345-347` | `deployNetworkToAWS` | thanos-stack (메인 인프라) |

`terraform output -json` 호출은 read-only 라 제외. `terraform.go` 의
destroy 명령은 본 fix scope 외 — 별도 검토 필요.

회귀 가드: `terraform_input_false_test.go` 가 두 파일의 백틱
raw-string 안에서 모든 `terraform <init|plan|apply>` 라인을 grep 으로
검사, `-input=false` 누락 시 fail. 미래에 새 호출 추가 시 동일 규칙을
강제.

이 디펜스로 차단되는 것: 어떤 사유로든 required 변수가 누락되거나
backend reconfigure / state migration 같은 인터랙티브 프롬프트가
발생할 때, hang 대신 즉시 에러 메시지와 함께 종료. backend
orchestrator 가 deployment 를 Failed 로 정상 전이 가능.

## 진단 체크리스트

deployment 가 step `deploy-aws-infra` 에서 멈췄을 때:

1. `docker exec trh-backend ps -ef | grep terraform` → `terraform plan` 살아 있나
2. DB `logs` 테이블 마지막 row 가 `var.<something>` ANSI 라인인가 → unset variable hang
3. `.envrc` 가 `${TF_VAR_<x>}` 를 참조하면서 정작 `export TF_VAR_<x>=` 라인이 없는가
4. 해당 모듈의 `variables.tf` 가 default 없는 required 인가

## 관련 파일

| 파일 | 역할 |
|------|------|
| `trh-sdk/pkg/stacks/thanos/input.go:1828` | `makeBlockExplorerEnvs` — .envrc 재작성, 본 hang 의 데이터 버그 위치 |
| `trh-sdk/pkg/stacks/thanos/input.go:1660` | `makeTerraformEnvFile` — 최초 .envrc 생성 (정상적으로 thanos_stack_name 기록) |
| `trh-sdk/pkg/stacks/thanos/block_explorer.go:67,340` | hang 을 유발한 호출자 두 곳 (Install/Update) |
| `trh-sdk/pkg/stacks/thanos/block_explorer_envrc_test.go` | 회귀 가드 |
| `tokamak-thanos-stack/terraform/block-explorer/variables.tf` | required `thanos_stack_name` 선언 |
