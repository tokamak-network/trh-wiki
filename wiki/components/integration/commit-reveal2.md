---
updated: 2026-04-17
sources: []
related:
  - "[[drb-project]]"
  - "[[drb-node]]"
  - "[[trh-sdk]]"
tags: [component, integration]
---

# Commit-Reveal2

> Part of the [[drb-project]] umbrella — protocol flow, round state machine, operator lifecycle, dispute/slashing은 그쪽을 참조.

**Tokamak Network의 분산 랜덤 비컨(DRB) 스마트 컨트랙트 구현체**. 기존 Commit-Reveal 방식의 "last revealer attack" 취약점을 제거한 2단계 reveal 프로토콜.

NPM 패키지: `@tokamak-network/commit-reveal2-contracts` v1.0.0

---

## 문제와 해결

**기존 문제**: 마지막으로 reveal하는 참가자가 최종 랜덤값을 보고 reveal 여부를 전략적으로 결정 가능 → 조작 가능한 랜덤성

**해결**: 2단계 reveal로 순서를 사전에 결정
1. **Phase 1 (Commit + Reveal-1)**: 중간값 Ωᵥ 생성
2. **Phase 2 (Reveal-2)**: `dᵢ = hash(|Ωᵥ - Cᵥ,ᵢ|)` 로 reveal 순서를 랜덤화 → 누구도 마지막 순서를 선점 불가

---

## 기술 스택

| 항목 | 버전 |
|------|------|
| Solidity | 0.8.30 |
| Build | Foundry (forge) |
| OpenZeppelin | v5.4.0 |
| solady | v0.1.24 |
| 서명 표준 | EIP-712 |

---

## 컨트랙트 구조

```
CommitReveal2.sol               ← 메인 진입점 (activation threshold, flat fee)
    └── FailLogics.sol          ← 참가자/리더 실패 처리
        └── DisputeLogics.sol   ← 분쟁 해결 (COS/S 미제출 시 슬래싱)
            └── OperatorManager.sol  ← Operator 등록/활성화/예치금 (최대 32명)
                └── CommitReveal2Storage.sol  ← 상태 저장 + EIP-712 도메인
```

**L2 변형**: `CommitReveal2L2.sol` — Optimism OVM_GasPriceOracle로 L1 데이터 수수료 계산

**소비자 인터페이스**: `ConsumerBase.sol` — 랜덤성을 요청하는 외부 컨트랙트용 추상 기반 클래스

---

## 프로토콜 상태

| 상태 | 값 | 설명 |
|------|-----|------|
| `IN_PROGRESS` | 1 | 라운드 진행 중 |
| `COMPLETED` | 2 | 라운드 완료 |
| `HALTED` | 3 | 실패로 인한 시스템 중단 |

---

## 디렉토리 구조

```
Commit-Reveal2/
├── src/               # 컨트랙트 소스
│   ├── CommitReveal2.sol
│   ├── CommitReveal2L2.sol
│   ├── CommitReveal2Storage.sol
│   ├── FailLogics.sol
│   ├── DisputeLogics.sol
│   ├── OperatorManager.sol
│   ├── ConsumerBase.sol
│   └── libraries/Bitmap.sol
├── script/            # 배포 스크립트 (Foundry)
├── test/              # 단위/가스/퍼즈 테스트
├── artifacts/         # 컴파일된 ABI (JSON)
└── output/            # 가스 분석 리포트
```

---

## 빌드 & 배포

```bash
make install && make build

# 테스트
make test
make fuzz_test

# 배포
make deploy                              # Anvil (local)
make deploy ARGS="--network sepolia"    # Ethereum Sepolia
make deploy ARGS="--network thanossepolia"  # Thanos Sepolia
```

---

## Genesis Predeploy 방식 (trh-sdk 전용)

Gaming/Full preset으로 배포된 Thanos L2에서는 CommitReveal2L2가 **genesis에 predeploy**된다. Foundry `make deploy`와 달리:

| 항목 | `make deploy` (전통적) | trh-sdk genesis predeploy |
|------|---------------------|--------------------------|
| 배포 시점 | 체인 운영 중 트랜잭션 | L2 genesis.json alloc 주입 |
| 가스 소모 | 있음 | 0 (genesis 상태) |
| 주소 | 배포자 nonce 기반 | `0x4200000000000000000000000000000000000060` (고정) |
| 검증 | etherscan | `cast code <addr>` |
| 프로세스 | Forge script | Go 시뮬레이션(`runtime.Create`) + alloc patch |

**구현 경로**: `trh-sdk/pkg/stacks/thanos/drb_genesis.go`의 `injectDRBIntoGenesis()`.
`@tokamak-network/commit-reveal2-contracts@1.0.0` npm 아티팩트에서 bytecode를 다운받아 Cancun EVM에서 생성자를 시뮬레이션한 뒤, 런타임 bytecode를 `0xc0D3…0060`(implementation) 슬롯에 배치하고 proxy(`0x4200…0060`)의 ERC1967 implementation slot을 설정한다.

**조건부**: Gaming 또는 Full preset에서만 주입됨 (General/DeFi는 skip).

---

## 네트워크 지원

- Ethereum Sepolia
- Optimism Sepolia
- Thanos Sepolia (Blockscout 검증 포함)

---

## Operator 상세 (OperatorManager.sol)

- **최대 Operator 수**: `MAX_ACTIVATED_OPERATORS = 32` (`MAX_OPERATOR_INDEX = 31`, 1-based 인덱싱)
- **활성화 조건**: `depositAmount ≥ s_activationThreshold` && 오너(Leader 주소)는 activate 불가
- **슬래시 보상**: X8 fixed-point(`s_slashRewardPerOperatorX8`) MasterChef 패턴으로 분배. 활성화 시점 이전 슬래시 보상은 소급 적용 안 됨
- **인출 Gate**: `notInProcess` 수식자로 `IN_PROGRESS` 중 인출/비활성화 차단
- **원자적 등록**: `depositAndActivate()` 로 예치+활성화 한 번에 처리

---

## 테스트 구조

| 경로 | 내용 |
|------|------|
| `test/staging/CommitReveal2Flowchart.t.sol` | 성공 8가지(a~h) + 실패 23가지(i~w) 전체 경로 |
| `test/fuzz/` | 퍼즈 테스트 (1000 runs) |
| `test/gas/ForManuscriptGas.t.sol` | 논문 제출용 가스 측정 수치 |
| `test/unit/` | 단위 테스트 |

---

## TRH 레포와의 관계

- **[[drb-project]]** → 두 레포를 DRB 프로젝트로 묶은 umbrella 페이지
- **[[drb-node]]** → 이 컨트랙트와 직접 상호작용하는 Go 노드 구현체
- **trh-sdk** → DRB 서비스를 Gaming/Full Preset에서 활성화 가능한 구조 (DRB 관련 배포 로직은 SDK에서 관리)
- ABI는 `artifacts/` 에서 추출해 다른 레포에서 import 가능 (단, DRB-node는 수동 복사 방식 — [[drb-project]] ABI Sync 섹션 참조)
