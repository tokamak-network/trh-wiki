---
updated: 2026-06-10
sources:
  - tokamak-thanos PR #396 (fix/emergency-exit-security)
  - docs/superpowers/specs/2026-06-09-contract-asset-emergency-exit-implementation-plan.md
  - docs/superpowers/specs/2026-06-10-contract-asset-emergency-exit-security-audit.html
related:
  - "[[tokamak-thanos]]"
  - "[[deposit-tx]]"
  - "[[tech-debt-and-risks]]"
tags: [concept, security, contracts]
---

# Contract Asset Emergency Exit

L2 앱 컨트랙트(DEX 풀, 스테이킹, 게임 등)에 잠긴 사용자 자산을 시퀀서/오퍼레이터 협조 없이 L1으로 강제 출금하는 메커니즘. `tokamak-thanos/packages/tokamak/contracts-bedrock` 에 구현 (`src/emergency-exit/`, `src/libraries/EmergencyExitProof.sol`).

---

## 두 가지 출금 경로

### 1) L2-native — Force TX
- `IEmergencyExitable` / `EmergencyExitableBase`(추상): 앱 컨트랙트가 상속하고 `_unwindPosition(user)`만 구현.
- 사용자가 L1 `OptimismPortal.depositTransaction`(Force TX, [[deposit-tx]])으로 L2의 `emergencyExit()` 호출 → 포지션 청산 → `L2StandardBridge.withdraw`로 표준 7일 출금.
- 운영자 게이트(`whenNotPaused`, `onlyActive` 등) 없음 — 검열 저항.

### 2) L1 resolver — MPT 증명
- 수정 불가능한 기존 ERC-20 컨트랙트용. `AppExitCoordinator`(L1) + `EmergencyExitProof`(라이브러리).
- registrar가 L2 토큰을 balance storage slot과 함께 등록(48h timelock — guardian이 취소 가능) → 활성화.
- guardian이 `declareEmergency(blockNumber)`로 **단일 스냅샷 블록** 고정.
- 사용자가 `eth_getProof`로 스냅샷 블록의 잔액 증명 수집 → `exitViaProof()` → 검증 후 L1 리저브에서 즉시 지급.

---

## 보안 설계 결정 (Why)

1차 구현에 HIGH 2건 + 경미 2건의 결함이 있었고, 보안 감사 후 수정(PR #396).

### D1. replay 방지 — 사용자 blockNumber 제거, guardian 고정 스냅샷
- **문제**: claim 키가 `(token, user, blockNumber)`이고 blockNumber를 사용자가 지정. L2 잔액은 소각되지 않으므로 동일 잔액을 여러 finalized 블록에서 반복 증명·청구 → 리저브 고갈.
- **결정**: 요청에서 `blockNumber` 제거, guardian이 `declareEmergency`로 고정한 단일 `emergencyBlockNumber`만 사용. claim 키 = `(token, user)` → 잔액당 1회.
- **트레이드오프**: 리졸버 경로는 수정 불가 컨트랙트 대상이라 L2 nullifier 불가. 스냅샷은 반드시 **비상 동결(freeze) 높이**여야 하고, 리저브는 그 높이의 전체 적격 잔액 기준으로 산정. 출금은 전액(all-or-nothing).

### D2. storage 증명 — SecureMerkleTrie + 값 RLP 이중 디코딩
- state/storage 트라이는 secure trie(키를 keccak256). 1차 구현은 raw 키로 `MerkleTrie`를 직접 호출 → 정상 `eth_getProof` 증명이 전부 실패(기능 불능).
- 또한 storage leaf 값은 `RLP(slotValue)`이고 `MerkleTrie.get`은 그 blob을 그대로 반환하므로 **한 번 더 디코딩** 필요. 안 하면 잔액 ≥ 0x80에서 RLP 길이 접두 바이트가 최상위 바이트로 섞여 **over-claim(탈취)** 가능. (결정적 근거: `OptimismPortal2`가 출금 증명에 `_value: hex"01"`=`RLP(1)`을 기대값으로 사용.)
- **결정**: account·storage 양쪽 `SecureMerkleTrie` 사용 + 값은 `RLPReader.readBytes`로 디코딩.

### D3. L2 정체성 — msg.sender 직접 사용
- 1차 구현은 `emergencyExit`에서 무조건 `undoL1ToL2Alias(msg.sender)`. 그러나 OptimismPortal은 **L1 컨트랙트 발신자만** alias 적용(`from = applyL1ToL2Alias(sender) iff sender != tx.origin`) → EOA Force TX(주 경로)는 un-aliased라 `sender - offset`이라는 잘못된 주소를 계산.
- **결정**: `msg.sender`를 그대로 L2 owner로 사용. EOA(직접/Force TX)와 aliased L1 컨트랙트 모두 일관.

### D4. activateToken 미등록 가드
- 접근 제어가 없고 미등록 레코드는 `activatesAt == 0`이라 timelock 검사를 통과 → 임의 주소를 active로 만들 수 있었음. `NotRegistered`(`l1Token == address(0)`) 가드 추가.

---

## 신뢰 모델 / 운영
- **registrar**: 토큰 등록 + 리저브 회수. **guardian**: 등록 취소 + `declareEmergency`(새 신뢰 기반 — 키 관리가 리졸버 경로를 좌우).
- 48h timelock으로 악의적 등록을 guardian이 취소할 시간 확보.
- L1 리저브 규모 = 스냅샷 높이의 전체 적격 잔액 가정.

## 검증
- `forge test --match-path "test/emergency-exit/*"` → **39 passed**. 실제 2단계 MPT 증명을 in-memory로 구성하는 `test/emergency-exit/MptProofBuilder.sol`로 키 해싱·값 디코딩·replay·over-claim 회귀를 커버.
- 상세: 보안 감사 보고서 `docs/superpowers/specs/2026-06-10-contract-asset-emergency-exit-security-audit.html`, PR #396.

## 함정 (pitfall)
- `ExitProofRequest`에서 `blockNumber` 제거 = **ABI 변경** → 오프체인 prover/keeper도 함께 수정해야 함.
- 리졸버 지급은 L2 잔액을 소비하지 않음 → 스냅샷 이전에 정상 브리지로 이미 출금한 사용자도 청구 가능. 그래서 스냅샷은 동결 높이여야 함.
