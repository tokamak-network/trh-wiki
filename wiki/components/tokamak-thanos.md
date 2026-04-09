---
updated: 2026-04-09
sources: []
related:
  - "[[tokamak-thanos-geth]]"
  - "[[tokamak-thanos-stack]]"
  - "[[trh-sdk]]"
  - "[[l2-deployment]]"
  - "[[deposit-tx]]"
tags: [component]
---

# tokamak-thanos

Tokamak Network의 **Thanos L2 Rollup 스택 핵심 레포**. Optimism OP Stack v1.7.7을 포크한 Go + TypeScript 모노레포.

---

## 역할

L2 롤업 운영에 필요한 노드 소프트웨어(op-node, op-batcher, op-proposer), 스마트 컨트랙트, TypeScript SDK를 모두 포함하는 상위 레포. trh-sdk와 trh-platform이 이 스택 위에서 동작한다.

---

## 기술 스택

| 항목 | 버전 |
|------|------|
| Go | 1.24.0 |
| TypeScript | 5.4.5 |
| Node.js | >=20 |
| pnpm | >=9 |
| Nx (모노레포) | 18.2.2 |
| Solidity | Foundry (forge) |

---

## 디렉토리 구조

```
tokamak-thanos/
├── op-node/              # L2 합의 계층 클라이언트
├── op-batcher/           # L2→L1 배치 제출자
├── op-proposer/          # L2 상태 루트 제안자
├── op-challenger/        # Dispute game 챌린저
├── op-service/           # 공통 Go 유틸리티
├── op-program/           # Fault proof 프로그램
├── op-e2e/               # E2E 테스트
├── op-chain-ops/         # 체인 상태 유틸리티
├── cannon/               # Fault proof 실행 환경
├── packages/tokamak/
│   ├── contracts-bedrock/   # Solidity 컨트랙트
│   ├── sdk/                 # @tokamak-network/thanos-sdk
│   ├── core-utils/          # @tokamak-network/core-utils
│   └── chain-mon/           # 체인 모니터링 서비스
└── proxyd/               # RPC 라우터
```

---

## 핵심 구성 요소

| 패키지 | 언어 | 역할 |
|--------|------|------|
| op-node | Go | L2 합의 클라이언트 — L1 동기화, 블록 검증 |
| op-batcher | Go | L2 트랜잭션 배치 → L1 제출 |
| op-proposer | Go | L2 상태 루트 → L1 정기 제안 |
| op-challenger | Go | Fault proof 분쟁 게임 참여 |
| contracts-bedrock | Solidity | OptimismPortal, L2OutputOracle 등 핵심 컨트랙트 |
| @tokamak-network/thanos-sdk | TypeScript | Thanos 상호작용 도구 (v0.0.14) |

---

## 빌드

```bash
make build       # Go + TypeScript 전체
make build-go    # Go 바이너리만 (op-node, op-batcher, op-proposer)
pnpm build       # TypeScript 패키지만
```

Docker 이미지: `docker-bake.hcl` 기반 멀티플랫폼 빌드

---

## TRH 레포와의 관계

- **trh-sdk** → tokamak-thanos의 Go 바이너리(op-node 등)를 Docker로 실행, contracts-bedrock ABI 활용
- **tokamak-thanos-geth** → 실행 계층(op-geth 역할)으로 op-node와 Engine API로 연동
- **tokamak-thanos-stack** → 이 레포의 컴포넌트들을 K8s/Helm으로 배포

---

## 주요 설정 파일

| 파일 | 용도 |
|------|------|
| `.env.example` | L1 RPC, Native Token 설정 |
| `versions.json` | abigen, foundry, geth, kontrol 버전 고정 |
| `docker-bake.hcl` | Docker 빌드 레이어 |
