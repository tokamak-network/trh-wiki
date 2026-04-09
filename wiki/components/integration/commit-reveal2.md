---
updated: 2026-04-09
sources: []
related:
  - "[[drb-node]]"
  - "[[trh-sdk]]"
tags: [component, integration]
---

# Commit-Reveal2

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

## 네트워크 지원

- Ethereum Sepolia
- Optimism Sepolia
- Thanos Sepolia (Blockscout 검증 포함)

---

## TRH 레포와의 관계

- **[[drb-node]]** → 이 컨트랙트와 직접 상호작용하는 Go 노드 구현체
- **trh-sdk** → DRB 서비스를 Gaming/Full Preset에서 활성화 가능한 구조 (DRB 관련 배포 로직은 SDK에서 관리)
- ABI는 `artifacts/` 에서 추출해 다른 레포에서 import 가능
