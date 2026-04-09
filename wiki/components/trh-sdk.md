---
updated: 2026-04-09
sources:
  - raw/architecture/tech-stack.md
related:
  - "[[architecture]]"
  - "[[trh-backend]]"
  - "[[presets]]"
  - "[[l2-deployment]]"
  - "[[deposit-tx]]"
  - "[[cross-trade]]"
tags: [component]
---

# trh-sdk

Go 1.24 기반 CLI 배포 엔진. trh-backend가 Go import로 직접 호출한다.

---

## 핵심 역할

- L2 롤업 배포 오케스트레이션 (L1 컨트랙트 → L2 노드 → 모듈)
- Preset별 genesis config, predeploy, 체인 파라미터 관리
- AWS 인프라 프로비저닝 (Terraform, Helm, EC2)
- Docker Compose 기반 로컬 L2 노드 실행
- CrossTrade 통합 (L1 Deposit Tx 패턴) → [[deposit-tx]], [[cross-trade]]

---

## 기술 스택

| 항목 | 버전 | 용도 |
|------|------|------|
| Go | 1.24 | 언어 |
| urfave/cli | v3.0.0-beta1 | CLI 프레임워크 |
| go-ethereum | 1.17.1 | Ethereum 클라이언트, ABI 인코딩 |
| aws-sdk-go-v2 | 1.41.1 | AWS (EC2, S3, DynamoDB, CloudWatch) |
| Terraform | 1.9.8 | 인프라 IaC |
| Helm | 3.16.3 | K8s 패키지 관리 |
| zap | 1.27.0 | 구조화 로깅 |
| holiman/uint256 | 1.3.2 | 256비트 정수 |
| go-bip32/go-bip39 | 1.0.0/1.1.0 | HD 지갑, 니모닉 |

---

## 패키지 구조 (주요)

```
pkg/stacks/thanos/
├── deploy_chain.go          — 체인 배포 메인 플로우
├── cross_trade_local.go     — CrossTrade 로컬 배포 (L1 Deposit Tx)
├── aa_setup.go              — Account Abstraction 셋업
├── drb_genesis.go           — DRB VRF genesis predeploy
└── register_candidate.go    — L2 후보 등록

abis/
├── TON.go                   — abigen 바인딩 예시
└── L1ContractVerification.go
```

---

## ABI 패턴

SDK는 두 가지 컨트랙트 호출 패턴을 사용한다:

| 패턴 | 사용 위치 | 특징 |
|------|---------|------|
| `abigen` 바인딩 | OptimismPortal, TON 등 직접 L1 호출 | 타입 안전, 컴파일 타임 검증 |
| `abi.JSON` + `Pack` | Deposit Tx 내부 L2 calldata | 런타임 인코딩, `drb_genesis.go` 패턴 |

→ [[abigen-vs-manual-calldata]]

---

## 트랜잭션 패턴

```go
// 표준 패턴 (deploy_chain.go, aa_setup.go)
opts := &bind.TransactOpts{...}
tx, err := contract.Method(opts, args...)
receipt, err := bind.WaitMined(ctx, client, tx)
```

`bind.WaitMined`가 reorg·타임아웃 엣지케이스를 처리한다.

---

## Docker Hub

- Image: `tokamaknetwork/trh-sdk`
- Architectures: linux/amd64 + arm64
