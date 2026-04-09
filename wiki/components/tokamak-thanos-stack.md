---
updated: 2026-04-09
sources: []
related:
  - "[[tokamak-thanos]]"
  - "[[tokamak-thanos-geth]]"
  - "[[trh-sdk]]"
  - "[[l2-deployment]]"
  - "[[ec2-deploy]]"
tags: [component]
---

# tokamak-thanos-stack

**Thanos L2 체인의 AWS 인프라 및 Kubernetes 배포 IaC 레포**. Terraform으로 AWS EKS를 프로비저닝하고, Helm으로 체인 노드와 서비스를 배포한다.

---

## 역할

trh-sdk가 AWS 배포 시 참조하는 Helm 차트와 Terraform 모듈의 원본 소스. `tokamak-thanos-stack install` 계열 명령어가 이 차트를 사용한다.

---

## 기술 스택

| 항목 | 버전 |
|------|------|
| Terraform AWS Provider | 5.17.0+ |
| Helm | v3.8+ |
| Kubernetes | 1.19+ / EKS 1.34 |

---

## 디렉토리 구조

```
tokamak-thanos-stack/
├── charts/
│   ├── thanos-stack/         # 핵심: OP Stack 노드 배포 (v1.0.6)
│   ├── blockscout-stack/     # Block Explorer (v6.10.0)
│   ├── monitoring/           # Prometheus + Grafana (v1.0.0)
│   ├── cross-trade/          # CrossTrade dApp (v1.0.0)
│   ├── op-bridge/            # Optimistic Bridge (v1.0.2)
│   └── uptime-service/       # Uptime Kuma (v1.23.16)
└── terraform/
    ├── thanos-stack/         # 메인 인프라 정의
    │   ├── thanos-stack.tf
    │   ├── modules/
    │   │   ├── vpc/
    │   │   ├── eks/
    │   │   ├── efs/          # 블록체인 데이터 영속성
    │   │   ├── kubernetes/   # Helm release 관리
    │   │   ├── secretsmanager/
    │   │   ├── chain-config/ # genesis.json, rollup.json → S3
    │   │   └── rds/
    │   └── scripts/          # generate-thanos-stack-values.sh
    ├── block-explorer/
    └── variables/
```

---

## Helm 차트 목록

| 차트 | 버전 | 역할 |
|------|------|------|
| thanos-stack | 1.0.6 | op-geth, op-node, op-batcher, op-proposer, op-challenger |
| blockscout-stack | 6.10.0 | Block Explorer |
| monitoring | 1.0.0 | Prometheus + Grafana + AlertManager |
| cross-trade | 1.0.0 | CrossTrade dApp (AWS용) |
| op-bridge | 1.0.2 | Optimistic Bridge |
| uptime-service | 1.23.16 | Uptime Kuma |

---

## Terraform 배포 흐름

```
1. terraform/backend/ → S3 + DynamoDB 상태 저장소 초기화
2. terraform/thanos-stack/ → VPC, EKS, EFS, SecretsManager 생성
3. kubernetes 모듈 → Helm 차트 배포
4. generate-thanos-stack-values.sh → deployments.json 파싱 → values.yaml 동적 생성
```

**필수 환경 변수** (`terraform/.envrc`):

| 변수 | 설명 |
|------|------|
| `TF_VAR_thanos_stack_name` | 스택 이름 |
| `TF_VAR_aws_region` | AWS 리전 (기본: ap-northeast-2) |
| `TF_VAR_sequencer_key` | Sequencer 개인키 |
| `TF_VAR_batcher_key` | Batcher 개인키 |
| `TF_VAR_stack_deployments_path` | deployments JSON 경로 |
| `TF_VAR_stack_l1_rpc_url` | L1 RPC URL |

---

## trh-sdk와의 관계

- trh-sdk의 `install monitoring`, `uninstall monitoring` 명령이 이 레포의 monitoring 차트를 호출
- trh-sdk가 `values-override.yaml`을 동적으로 생성해 Helm 배포에 주입
- AWS 배포 시 이 레포의 Terraform 모듈을 통해 전체 인프라 생성

---

## Local vs AWS 차이

| 항목 | Local (Docker Compose) | AWS (tokamak-thanos-stack) |
|------|----------------------|--------------------------|
| 인프라 | docker-compose.yml | Terraform + EKS |
| 노드 배포 | Docker 컨테이너 | Helm Chart (thanos-stack) |
| 데이터 저장 | 로컬 볼륨 | AWS EFS |
| 키 관리 | env 파일 | AWS Secrets Manager |
| CrossTrade | docker-compose.crosstrade.yml | cross-trade Helm 차트 |
