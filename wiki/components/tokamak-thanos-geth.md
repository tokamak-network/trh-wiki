---
updated: 2026-04-09
sources: []
related:
  - "[[tokamak-thanos]]"
  - "[[tokamak-thanos-stack]]"
  - "[[deposit-tx]]"
  - "[[l2-deployment]]"
tags: [component]
---

# tokamak-thanos-geth

**Thanos L2 실행 계층(Execution Client)**. go-ethereum v1.16.3를 기반으로 OP Stack 수정을 적용한 포크. op-node와 Engine API로 통신하는 op-geth 역할을 한다.

---

## 포크 관계

```
go-ethereum (upstream)
    └── op-geth (ethereum-optimism)
            └── tokamak-thanos-geth (이 레포)
```

- Go 1.23.0
- upstream 기반: go-ethereum v1.16.3 (hash: `d818a9af`)

---

## OP Stack 추가 사항 (op-geth 공통)

op-geth 포크로서 가지는 기본 수정:

| 항목 | 설명 |
|------|------|
| Deposit TX (0x7E) | L1→L2 상태 변경 트랜잭션 타입 추가 |
| L1 Cost 계산 | 트랜잭션당 L1 데이터 가스 비용 추가 |
| Engine API 확장 | 트랜잭션 삽입, tx-pool 토글, 가스리밋 동적 설정 |
| Gaslimit 자유화 | 1/1024 증분 제약 제거 |
| Chain Config | `optimism` 필드, EIP-1559 파라미터 조정 |
| TTD=0 | post-merge 즉시 시작 |

---

## Tokamak 추가 수정 (op-geth 대비)

| EIP | 내용 |
|-----|------|
| EIP-7825 | 트랜잭션 가스 리밋 상한 (2^24) |
| EIP-7918 | Blob 기본 비용 제약 |
| EIP-7892 | Blob 파라미터 전용 하드포크 (Cancun → Prague → Osaka → BPO1-5) |
| EIP-7910 | `eth_config` RPC 메서드 추가 |
| PeerDAS | Blob 사이드카 버전 관리, KZG 증명 검증 |
| Pectra | Pectra 하드포크 지원 |

---

## 핵심 파일

| 파일 | 역할 |
|------|------|
| `core/types/deposit_tx.go` | Deposit TX 타입 정의 |
| `core/types/rollup_cost.go` | L1 비용 계산 로직 |
| `core/state_processor.go` | Deposit TX 특수 처리 (가스 선지급, EVM 실패 처리) |
| `eth/catalyst/api.go` | Engine API 확장 |
| `params/config.go` | 포크 설정 (Optimism, Cancun, Prague, BPO1-5) |

---

## 빌드

```bash
make geth    # geth 바이너리만
make all     # 모든 도구 (abigen, evm, bootnode 등)
```

Docker: `Dockerfile` (Go 1.24-alpine 기반, 정적 바이너리)

---

## 배포에서의 위치

```
op-node (tokamak-thanos)
    │  Engine API (authenticated RPC, port 8551)
    ▼
tokamak-thanos-geth          ← 이 레포
    │  HTTP/WS RPC (8545/8546)
    ▼
L2 트랜잭션 처리 / 상태 저장
```

trh-sdk의 `docker-compose.yml`에서 `op-geth` 서비스 이미지로 사용됨.
