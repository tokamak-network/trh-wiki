---
updated: 2026-04-17
sources: []
related:
  - "[[drb-node]]"
  - "[[commit-reveal2]]"
  - "[[trh-sdk]]"
  - "[[presets]]"
tags: [component, integration]
---

# DRB Project

**Tokamak Distributed Random Beacon(DRB)** — 조작 불가능한 온체인 랜덤성을 제공하는 프로토콜. 두 개의 레포지토리로 구성된다.

| 레포 | 언어 | 역할 | 경로 |
|------|------|------|------|
| `Commit-Reveal2` | Solidity 0.8.30 | 온체인 프로토콜 컨트랙트 (state machine, slashing, random generation) | `/Users/theo/workspace_tokamak/Commit-Reveal2/` |
| `DRB-node` | Go 1.23 | 오프체인 노드 소프트웨어 (Leader + Regular 타입) | `/Users/theo/workspace_tokamak/DRB-node/` |

개별 레포 상세는 [[drb-node]], [[commit-reveal2]] 페이지를 참조.

---

## 문제와 해결

**기존 Commit-Reveal의 취약점**: 마지막 revealer가 최종 랜덤값을 미리 보고 reveal 여부를 전략적으로 결정 가능 → 랜덤성 조작.

**해결**: 2단계 reveal + 사전 순서 결정
1. **Phase 1**: Commit → 중간값 Ωᵥ 생성
2. **Phase 2**: `dᵢ = hash(|Ωᵥ - Cᵥ,ᵢ|)` 로 reveal 순서를 랜덤화 → 누구도 마지막 순서를 선점 불가

---

## End-to-End Protocol Flow

액터: **Consumer 컨트랙트 / CommitReveal2 컨트랙트 / Leader 노드 / Regular 노드들**

```
Consumer
  └─ requestRandomNumber()  ───────────────────────────► CommitReveal2 (상태: COMPLETED → IN_PROGRESS)

Regular 노드들 (Off-chain)
  └─ CVS(Commitment Value Signature) 생성 + Leader에 전송

Leader 노드 (Off-chain)
  └─ CVS 수집 → Merkle tree 구성

Leader 노드 (On-chain)
  └─ submitMerkleRoot()  ──────────────────────────────► CommitReveal2

Regular 노드들 (Off-chain)
  └─ COS(Commitment Opening Signature) 생성 + Leader에 전송

Leader 노드 (Off-chain)
  └─ COS 수집 → reveal 순서 결정

Regular 노드들 (Off-chain, ordered)
  └─ Secret 제출 → Leader에 전달

Leader 노드 (On-chain)
  └─ generateRandomNumber()  ──────────────────────────► CommitReveal2 (상태: IN_PROGRESS → COMPLETED)

CommitReveal2
  └─ Consumer 콜백  ───────────────────────────────────► Consumer 컨트랙트
```

**Ground truth 소스**: `Commit-Reveal2/test/staging/CommitReveal2Flowchart.t.sol` — 8가지 성공 경로(a~h)와 23가지 실패 경로(i~w)가 테스트로 정의되어 있음.

---

## Round State Machine

출처: `DRB-node/STATE_DIAGRAM.md`, `Commit-Reveal2/src/FailLogics.sol`, `DisputeLogics.sol`

```
[초기 배포] ──► COMPLETED
               │
               │ requestRandomNumber()
               ▼
           IN_PROGRESS
               │
     ┌─────────┴───────────────────────────────────────────┐
     │                                                     │
     │  OFF_CHAIN_SUBMISSION                               │
     │    → (타임아웃, 커밋 누락) → DISPUTE_CV             │
     │    → failToRequestSubmitCvOrSubmitMerkleRoot() ──► HALTED
     │                                                     │
     │  DISPUTE_CV → CV_SUBMISSION                         │
     │    → failToSubmitCv() ──────────────────────────► HALTED
     │    → failToSubmitMerkleRootAfterDispute() ────────► HALTED
     │                                                     │
     │  MERKLE_ROOT_SUBMISSION → submitMerkleRoot()        │
     │                                                     │
     │  DIRECT_GENERATION (COs 충분)                       │
     │    → failToRequestSOrGenerateRandomNumber() ─────► HALTED
     │                                                     │
     │  DISPUTE_CO → CO_SUBMISSION                         │
     │    → failToSubmitCo() ──────────────────────────► HALTED
     │                                                     │
     │  DISPUTE_S → S_SUBMISSION                           │
     │    → failToSubmitAllS() ────────────────────────► HALTED
     │                                                     │
     │  CALLBACK → Consumer 콜백                           │
     └─────────────────────────────────────────────────────┘
               │                        │
               ▼                        ▼
          COMPLETED                  HALTED
                                (수동 복구 필요)
```

**HALTED 상태**: 6가지 분기 모두 불가역적. 컨트랙트 오너의 수동 개입이 필요하며 일반적으로 재배포를 의미한다.

---

## Operator Lifecycle

출처: `Commit-Reveal2/src/OperatorManager.sol`

Operator = DRB-node Regular 노드 운영자. 컨트랙트에 예치금을 내고 활성화한 후 랜덤 생성 라운드에 참여한다.

```
deposit()                 ← ETH 예치 (활성화 임계값 미달이어도 가능)
    │
depositAndActivate()      ← 예치 + 즉시 활성화 (atomic)
    │
    ├─ 조건: 예치금 ≥ s_activationThreshold
    ├─ 조건: 이미 활성화된 상태가 아닐 것
    ├─ 조건: 오너(Leader)는 activate 불가
    └─ 조건: MAX_ACTIVATED_OPERATORS(32) 미만

activate()                ← 이미 예치된 상태에서 별도 활성화
    │
    └─ [라운드 참여 중 ...]

withdraw()                ← 예치금 + 누적 슬래시 보상 인출
    ├─ notInProcess 수식자: IN_PROGRESS 중에는 인출 불가
    └─ 자동 deactivate 처리
```

**최대 Operator 수**: `MAX_ACTIVATED_OPERATORS = 32` (`MAX_OPERATOR_INDEX = 31`, 1-based 인덱싱).

**슬래시 보상 분배 (X8 fixed-point)**: MasterChef 패턴과 동일. `s_slashRewardPerOperatorX8`(글로벌 누적)과 `s_slashRewardPerOperatorPaidX8[operator]`(개인 누적) 차이를 `>> 8`로 나눠서 정산. Operator가 활성화될 때 paid 값을 현재 글로벌 값으로 초기화하므로, 활성화 이전 슬래시에 대한 보상은 받지 못한다.

---

## Dispute & Slashing Matrix

| Regular 노드 실패 유형 | 호출되는 Halt 함수 | 슬래싱 대상 | DRB-node 대응 코드 |
|------------------------|-------------------|------------|---------------------|
| CVS 미제출 (타임아웃) | `failToRequestSubmitCvOrSubmitMerkleRoot()` | 해당 Regular 노드들 | `nodes/leader/accept_commit.go` |
| CV 제출 실패 | `failToSubmitCv()` | CV 미제출 노드 | `nodes/leader/monitor_commits.go` |
| Merkle root 재제출 실패 | `failToSubmitMerkleRootAfterDispute()` | Leader | `nodes/leader/leader_node.go` |
| CO 제출 실패 | `failToSubmitCo()` | CO 미제출 노드 | `nodes/leader/reveal_requests.go` |
| S (Secret) 요청/생성 실패 | `failToRequestSOrGenerateRandomNumber()` | Leader | `nodes/leader/reveal_requests.go` |
| 모든 S 제출 실패 | `failToSubmitAllS()` | S 미제출 노드 전체 | `nodes/regular/secret_handler.go` |

슬래시된 예치금은 `s_slashRewardPerOperatorX8`에 축적되어 정상 operator들에게 분배된다.

---

## Operator (Regular 노드) 등록 플로우

```
1. Regular 노드: depositAndActivate() 호출 (예치금 송금)
2. CommitReveal2: s_activatedOperators[] 에 추가
3. Leader 노드: StatusEvent 감지 → Regular 노드들 스캔
4. Regular 노드: CVS 생성 후 Leader에 LibP2P로 전송
5. (라운드 종료 후 계속 참여)
```

---

## L2 Gas Considerations

`CommitReveal2L2.sol`은 `IOVM_GasPriceOracle.sol`을 통해 **L1 데이터 수수료**를 calldata 비용에 가산한다. L1 베이스피에 따라 가스 비용이 크게 달라지므로 Thanos Sepolia 배포 시 수수료 계산 확인 필요.

네트워크별 제한(calldata size, gas limit 등)은 `DRB-node/docs/network-limits.md`를 참조.

---

## ABI Sync Workflow

`Commit-Reveal2`는 `@tokamak-network/commit-reveal2-contracts` npm 패키지로 배포되지만, **DRB-node는 npm을 import하지 않는다**.

```
Commit-Reveal2/artifacts/*.json   ←  forge build 결과 (ABI 포함)
        │
        │ (수동 복사)
        ▼
DRB-node/contract/abi/            ←  ABI JSON 저장소
        │
        │ abigen
        ▼
DRB-node/contract/leader/         ←  Leader용 Go 바인딩
DRB-node/contract/regular/        ←  Regular용 Go 바인딩
```

**컨트랙트 업그레이드 시**: ABI JSON 수동 복사 → `abigen` 재실행 → Go 바인딩 재생성 필요. 자동화 없음 — 업그레이드 시 주의.

---

## Environment Matrix

| 환경 | Chain ID | 네트워크 | 비고 |
|------|----------|----------|------|
| Anvil (local) | 31337 | 개발용 | `make deploy` |
| Ethereum Sepolia | 11155111 | 테스트넷 | `--network sepolia` |
| Optimism Sepolia | 11155420 | L2 테스트넷 | `--network optimismsepolia` |
| Thanos Sepolia | 111551132354 | TRH L2 테스트넷 | `--network thanossepolia` |

DRB-node 필수 환경 변수:

| 변수 | 설명 |
|------|------|
| `NODE_TYPE` | `leader` 또는 `regular` |
| `LEADER_PRIVATE_KEY` | Leader 트랜잭션 서명 키 |
| `LEADER_PEER_ID` | LibP2P Peer ID (generator 도구로 생성) |
| `ETH_RPC_URLS` | RPC 엔드포인트 콤마 구분 (페일오버 지원) |
| `CONTRACT_ADDRESS` | 배포된 CommitReveal2 컨트랙트 주소 |
| `CHAIN_ID` | 네트워크 체인 ID |
| `POSTGRES_*` | PostgreSQL 연결 정보 |

---

## Integration & Stress Testing

### DRB-node 테스트 (`integration_test/`)

```bash
# 1단계: 로컬 geth 기동
cd test/ && ./run_geth_test.sh   # 터미널 1

# 2단계: 통합 테스트 실행
go test ./integration_test -v -timeout 180m   # 터미널 2
```

주요 테스트 파일:
- `docker_nodes_quick_test.go` (128KB) — 기본 노드 동작 검증
- `integration_node_failure_test.go` — 노드 장애 시나리오
- `integration_performance_test.go` — 성능 측정
- `integration_stress_test.go` — 부하 테스트
- `run_race_tests.sh` — Go race detector 통합 (별도 CI gate)
- `INTEGRATION_TEST_COVERAGE.md` — 커버리지 매핑 문서

### Commit-Reveal2 테스트

```bash
make test          # 단위 테스트
make fuzz_test     # 퍼즈 테스트 (foundry.toml: 1000 runs)

# 가스 분석 (논문 수치 포함)
forge test --match-path "test/gas/ForManuscriptGas.t.sol" -vv
```

프로토콜 전체 경로(성공 8가지 + 실패 23가지)는 `test/staging/CommitReveal2Flowchart.t.sol`에 정의.

---

## TRH 생태계 연결

- **[[trh-sdk]]** → Gaming/Full [[presets]]에서 DRB-node Docker 컨테이너를 Docker Compose로 기동. 두 레포 내부에는 TRH 직접 참조 없음 — 단방향 의존(SDK → DRB-node).
- **Consumer 패턴** → 외부 dApp이 `ConsumerBase.sol`을 상속해 랜덤성 요청. DRB-node는 Consumer 컨트랙트와 직접 상호작용하지 않음.

---

## Known Quirks

- **Go 버전 불일치**: `go.mod`에는 `go 1.23.0`이지만 README에는 `Go 1.24+`를 요구사항으로 명시. `toolchain go1.23.9`가 실제 사용 버전.
- **HALTED 복구**: HALTED 상태에서 벗어나는 on-chain 메커니즘이 없음. 컨트랙트 재배포 필요.
- **Peer ID 생성**:
  - **일반 경로**: Leader/Regular 각각 `cmd/generator/`, `cmd/regulargenerator/` 도구 사용. `static-key/leadernode.bin` 안전 보관 필수.
  - **trh-sdk Gaming/Full preset 경로**: SDK가 libp2p Go 라이브러리로 seed phrase에서 결정적 파생(`sha256(mnemonic + "|drb-peer-id-v1|" + role)`). 재배포 시 동일 peer ID 재현. 도구 실행 불필요.
- **로컬 Gaming/Full preset 배포 구성**: **Leader + Regular 3대 고정**. `CommitReveal2L2.activationThreshold`만큼 genesis alloc 자동 funding (max(threshold×10, 1e18) native 토큰). SDK가 `depositAndActivate()` 순차 호출로 모든 operator 활성화 완료 상태로 배포 마감.
