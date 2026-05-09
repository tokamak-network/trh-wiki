---
updated: 2026-05-09
---

# Terraform Destroy — secretsmanager backend block 오류

## 증상

AWS 스택 destroy 시 다음 오류와 함께 `terraform destroy` 실패:

```
on modules/secretsmanager/backend.tf line 4, in terraform:
Any selected backend applies to the entire configuration, so Terraform expects
provider configurations only in the root module.
terraform destroy failed for .../terraform/thanos-stack: exit status 1
```

VPC destroy가 18-19분 진행되다가 위 에러로 중단됨.

## 근본 원인

`tokamak-thanos-stack/terraform/thanos-stack/modules/secretsmanager/backend.tf`에
`backend "s3" {}` 블록이 선언되어 있었음.

Terraform 1.x 규칙: **backend 블록은 root module에만 허용**, child module에는 금지.

이 블록은 secretsmanager가 독립 root module로 관리되던 레거시 코드. 이후
`thanos-stack.tf`에서 `module "secretsmanager" { source = "./modules/secretsmanager" }`
형태의 child module로 리팩토링됐으나 `backend.tf`가 제거되지 않은 채 남아있었음.

trh-sdk는 `-target=module.secretsmanager` 옵션으로 이 모듈을 child로 사용하므로
별도 terraform root로 실행하지 않는다.

## 수정

`tokamak-thanos-stack` 커밋 `1dd0d70`:
`modules/secretsmanager/backend.tf`에서 `backend "s3" {}` 블록 제거.

```hcl
# 수정 전 (잘못됨)
terraform {
  required_version = ">= 1.0.0"
  backend "s3" {
    key            = "tokamak-thanos-stack/terraform/init/secretsmanager/terraform.tfstate"
    ...
  }
}

# 수정 후
terraform {
  required_version = ">= 1.0.0"
}
```

## 수동 복구 절차 (이미 실패한 스택)

1. terraform state 확인: `terraform state list` → VPC만 남아있는 경우가 많음
2. VPC에 남아있는 Security Group을 먼저 삭제
3. VPC 직접 삭제: `aws ec2 delete-vpc --vpc-id <id>`
4. terraform state에서 VPC 제거: `terraform state rm "module.vpc.module.vpc.aws_vpc.this[0]"`
5. S3 tfstate 버킷 삭제 (버전 관리 활성화 시 versions + delete markers 먼저 삭제 후 버킷 삭제)
6. DynamoDB lock 테이블 삭제: `aws dynamodb delete-table --table-name <stack-name>-terraform-lock`

## 영향 범위

수정 전에 배포된 모든 스택의 terraform 코드에 이 파일이 복사되어 있으므로,
**이미 존재하는 배포본은 수동 복구 필요**.
신규 배포부터는 수정된 소스 코드가 적용됨.
