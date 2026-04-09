---
updated: 2026-04-09
sources: []
related:
  - "[[commit-reveal2]]"
  - "[[trh-sdk]]"
tags: [component, integration]
---

# DRB-node

**분산 랜덤 비컨(DRB) Go 노드 구현체**. Commit-Reveal2 스마트 컨트랙트와 상호작용하며 Leader / Regular 두 가지 노드 타입으로 분산 랜덤 넘버 생성 라운드를 조율한다.

---

## 역할

[[commit-reveal2]] 컨트랙트의 프로토콜을 off-chain에서 실행하는 노드 소프트웨어:
- **Leader 노드**: 라운드 조율, Merkle root 생성, reveal 순서 관리, 최종 랜덤값 on-chain 제출
- **Regular 노드**: Leader에 등록 후 CVS(Commitment Value Signature) → COS(Commitment Opening Signature) → Secret 순으로 제출

---

## 기술 스택

| 항목 | 버전 |
|------|------|
| Go | 1.23.0 |
| go-ethereum | v1.11.5 |
| libp2p | v0.37.1 |
| go-pg (PostgreSQL ORM) | v10.14.0 |
| logrus | v1.9.3 |
| 배포 | Docker + Docker Compose |

---

## 디렉토리 구조

```
DRB-node/
├── cmd/
│   ├── nodes/main.go            # 메인 진입점 (leader/regular 분기)
│   ├── generator/               # Leader Peer ID 생성기
│   └── regulargenerator/        # Regular Peer ID 생성기
├── nodes/
│   ├── leader/                  # LeaderNodeHandler
│   │   ├── leader_node.go       # 라운드 조율 핵심 로직
│   │   ├── accept_commit.go     # 이벤트 처리 및 모니터링
│   │   ├── monitor_commits.go   # 라운드 검증 및 완료 처리
│   │   └── reveal_requests.go   # Secret 요청 순서 관리
│   └── regular/                 # RegularNodeHandler
│       ├── regular_node.go      # 등록 및 참여 로직
│       ├── send_commit.go       # CVS 제출
│       └── secret_handler.go    # Secret reveal 처리
├── commit-reveal2/              # 프로토콜 암호화 로직
│   ├── commit.go                # CVS/COS 해시 생성
│   ├── merkleTree.go            # Merkle 증명 생성
│   └── reveal_order.go          # Reveal 순서 결정
├── contract/                    # 컨트랙트 Go 바인딩 (abigen)
├── database/                    # PostgreSQL 영속성 레이어
│   └── migrations/              # SQL 스키마 마이그레이션
├── eth/                         # Ethereum RPC 상호작용
│   └── interface.go             # IEthService 인터페이스
├── libp2putils/                 # LibP2P P2P 통신
├── pkg/fallback_ethclient/      # 다중 RPC 페일오버 클라이언트
└── test/                        # 테스트 환경 (1 leader + 3 regular)
```

---

## 프로토콜 흐름

```
Status Event 발생
    ↓
Regular 노드들: CVS 제출 (Commit Phase)
    ↓
Leader: Merkle root 생성 → 브로드캐스트
    ↓
Regular 노드들: COS 제출 (Opening Phase)
    ↓
Leader: reveal 순서 결정 → Sequential Secret 요청
    ↓
최종 랜덤값 → on-chain 제출 (CommitReveal2 컨트랙트)
```

---

## 환경 변수

| 변수 | 설명 |
|------|------|
| `NODE_TYPE` | `leader` 또는 `regular` |
| `LEADER_PRIVATE_KEY` | Leader 서명 키 |
| `LEADER_PEER_ID` | Leader LibP2P Peer ID |
| `ETH_RPC_URLS` | Ethereum RPC 엔드포인트 (콤마 구분, 페일오버 지원) |
| `CONTRACT_ADDRESS` | 배포된 CommitReveal2 컨트랙트 주소 |
| `CHAIN_ID` | 네트워크 체인 ID (예: 111551119090 = ThanosSepolia) |
| `POSTGRES_*` | PostgreSQL 연결 정보 |

---

## 빌드 & 실행

```bash
# 빌드
go build -o main ./cmd/nodes/main.go

# 테스트 환경 (1 leader + 3 regular)
cd test/ && ./build.sh

# 프로덕션 배포
cd deployment/leader/ && ./build.sh
cd deployment/regular/ && ./build.sh

# 단위 테스트
go test -v ./nodes/leader/... ./nodes/regular/...

# 통합 테스트
cd test/ && ./run_geth_test.sh  # 터미널 1
go test ./integration_test -v -timeout 180m  # 터미널 2
```

---

## TRH 레포와의 관계

- **[[commit-reveal2]]** → 이 노드가 상호작용하는 스마트 컨트랙트 (ABI 직접 import)
- **trh-sdk** → DRB 모듈 활성화 시 DRB-node 컨테이너를 Docker Compose로 기동하는 주체
- 직접 코드 의존성 없음 — Ethereum RPC + LibP2P로 독립 운영
