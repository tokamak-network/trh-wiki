---
updated: 2026-04-10
sources:
  - raw/architecture/deployment-pitfalls.md
  - raw/inbox/crosstrade-deployment-guide.md
---

# L1 Deposit Tx Pitfalls

CrossTrade L2 컨트랙트 배포 시 L1 Deposit Transaction 패턴에서 발생하는 주요 함정 13개.

**관련:** [[deposit-tx]], [[cross-trade]], [[l2-deposit-verification]]

---

## Critical (배포 실패 또는 영구 잠김)

### 1. Address Aliasing — Proxy onlyOwner 잠김

**현상:** `setSelectorImplementations2` 호출 시 "Accessible: Caller is not an admin" 에러

**원인:** EOA가 `OptimismPortal.depositTransaction()`을 직접 호출하면 L2 `msg.sender` = EOA 주소(aliasing 없음). 하지만 중간 컨트랙트를 통해 호출하면 L2 sender = `l1Address + 0x1111...1111` (aliased). Proxy 생성 시 ADMIN_ROLE이 등록된 주소와 이후 호출 주소가 달라져 모든 초기화 함수가 revert된다.

**방지:**
- 12개 deposit tx 전체를 동일한 메커니즘(EOA 또는 컨트랙트)으로 통일
- `DeployCrossTradeLocal()`에서 deployer 주소의 코드 존재 여부 검사: `len(code) == 0`
- 코드 주석: "DO NOT wrap these calls in a contract"

**신뢰도:** HIGH (OP Stack 스펙 + AccessibleCommon.sol 검증)

---

### 2. L2 Nonce 탈동기화 — 주소 예측 오류

**현상:** Steps 3-12가 잘못된 주소에 작동, 전체 배포 무결성 파괴

**원인:** Deposit tx는 L2에 반드시 포함되지만 revert될 수 있고, revert 시에도 L2 nonce는 증가한다. 중간 단계를 기다리지 않으면 CREATE 주소(`keccak256(sender, nonce)`)가 예측 값과 어긋난다.

**방지:**
- **각 deposit tx 후 L2 receipt 대기** — 다음 단계 진행 전 `receipt.Status == 1` 확인
- `waitForDepositTxL2Receipt()` 헬퍼 구현: L1 receipt → TransactionDeposited 이벤트 → L2 tx hash 폴링
- 배포 상태 파일에 단계별 완료 주소 저장 (중단 시 재개 가능)

**신뢰도:** HIGH

---

### 3. Gas 한도 불일치 — L2 실행 OOG revert

**현상:** L2 deposit tx가 out-of-gas로 revert (silently), 이후 Pitfall 2로 이어짐

**원인:** `depositTransaction()`의 `_gasLimit`은 L2 실행 가스이며 L1 가스가 아니다. 단일 flat 값(예: 3,000,000) 사용 시 컨트랙트 생성(대형 bytecode)과 함수 호출의 가스 요구량 차이를 수용 못함.

**방지:**
- 단계별 별도 gas limit 측정 (50% 안전 마진 추가)
- 생성 단계: `bytecodeSize * 200 + 21000 + constructorGas`
- 함수 호출 단계: L2 RPC에서 `eth_estimateGas` + 30% 마진

**신뢰도:** HIGH

---

### 4. setSelectorImplementations2 — upgradeTo 선행 누락

**현상:** Proxy 배포 후 모든 CrossTrade 함수 호출이 "Proxy: impl OR proxy is false" revert

**원인:** `setSelectorImplementations2` 호출 전 반드시 `upgradeTo(implAddress)` 또는 `setImplementation2(implAddress, 0, true)`가 먼저 실행되어야 한다. `aliveImplementation[impl] == true`가 전제 조건.

**방지:**
- 6-step 시퀀스에 `upgradeTo` 단계를 명시적으로 추가 (실질적으로 7-step)
- ABI에서 selector list를 프로그래밍 방식으로 생성 (하드코딩 금지)
- 배포 후 view 함수 호출로 라우팅 동작 검증

**신뢰도:** HIGH (Proxy.sol 소스 코드 검증)

---

### 5. setChainInfo L2 vs L1 Owner 키 혼동

**현상:** L1 setChainInfo tx가 "Accessible: Caller is not an admin" revert

**원인:** L2 setChainInfo(Deposit Tx, deployer가 호출)와 L1 setChainInfo(Backend가 호출, L1 컨트랙트 owner 필요)는 별개의 권한 체계. Phase 1은 `deployer == L1 owner`를 가정하지만 이는 단순화.

**방지:**
- `CrossTradeL1RegistrationInput`에 `L1OwnerPrivateKey`를 `DeployerPrivateKey`와 분리
- 사전 체크: `L1CrossTradeProxy.isAdmin(ourAddress)` 호출 후 진행

**신뢰도:** HIGH

---

## Moderate (배포는 성공하지만 기능 장애)

### 6. Go 모듈 Pseudo-version 의존성 (trh-sdk ↔ trh-backend)

**현상:** `go build` 실패 "unknown revision" 또는 로컬 replace 포함 커밋이 CI에서 실패

**방지:**
- 개발 중 `replace github.com/tokamak-network/trh-sdk => /local/path` 사용
- 커밋 전 replace 제거 확인 CI 체크 추가

---

### 7. L2 Receipt 폴링 — 잘못된 tx 매핑

**현상:** L1 tx hash로 L2 receipt 조회 시 결과 없음 또는 엉뚱한 tx

**원인:** L1 tx hash ≠ L2 tx hash. L2 deposit tx hash는 `sourceHash = keccak256(bytes32(0), keccak256(l1BlockHash, uint256(logIndex)))`로 별도 계산해야 한다.

**방지:**
- `TransactionDeposited` 이벤트에서 `opaqueData` 파싱
- OP Stack 공식 formula로 L2 deposit tx hash 계산
- `optimism_getDepositReceipt` RPC 사용 (L2 노드 지원 시)

---

### 8. CrossTrade dApp — 컨트랙트 배포 전 조기 시작

**현상:** dApp이 계약 주소 없이 시작되어 빈 UI 또는 크래시

**원인:** Docker Compose `depends_on`은 컨테이너 시작만 보장하며 앱 레벨 준비도를 보장 않음. CrossTrade 배포는 Backend 헬스체크 수분 후 완료됨.

**방지:**
- Docker Compose profile로 opt-in 서비스 구성: `docker compose --profile crosstrade up -d`
- Backend가 배포 성공 후에만 `.env.crosstrade` 생성 및 dApp 기동

---

### 9. ReentrancyGuard — Proxy 스토리지 초기화 누락

**현상:** `nonReentrant` 함수 첫 호출이 revert되거나 재진입 방지가 동작 않음

**원인:** Implementation constructor가 자신의 스토리지에 `_status = 1` 설정. 하지만 delegatecall은 proxy 스토리지를 사용하므로 proxy의 `_status`는 기본값 0.

**방지:**
- 실제 `ReentrancyGuard.sol` 구현 확인 (NOT_ENTERED = 0 또는 1 여부)
- `_NOT_ENTERED = 1`이면 proxy에서 `initialize()`로 스토리지 초기화 필요

---

### 10. registerToken — 잘못된 L2 토큰 주소

**현상:** CrossTrade 요청이 "CT: The tokens are not registered" revert

**방지:**
- L2 토큰 주소를 배포 output/genesis config에서 프로그래밍 방식으로 읽기 (하드코딩 금지)
- 등록 후 `registerCheck[chainId][l1Token][l2Token]` 검증 호출

---

## Minor (운영 중 간헐적 문제)

### 11. L1 Nonce Race — Sequential Deposit Txs

**방지:** 시작 시 nonce 한 번 조회 후 로컬 카운터로 관리. 각 tx마다 `PendingNonceAt` 재조회 금지.

### 12. localUnsupported 맵 제거 — 암묵적 Feature Flag

**방지:** SDK + Backend + dApp E2E 테스트 완료 전에 `localUnsupported`에서 제거 금지.

### 13. L2toL2CrossTrade setChainInfo — 다른 파라미터 시그니처

**현상:** L2toL2 setChainInfo가 L2→L1 성공 후 L2 revert

**방지:** L2CrossTradeProxy와 L2toL2CrossTradeProxy에 대해 별도 ABI 바인딩 생성. 함수 시그니처 사전 검증.

---

### 14. L2toL2CrossTradeProxy — upgradeTo 없이 setChainInfo 성공, 나머지 전부 silent broken

**현상:** `setChainInfo` 호출 성공 → 체인 등록 완료로 착각 → 이후 모든 함수 "Proxy: impl OR proxy is false" revert

**원인:** `L2toL2CrossTradeProxy.setChainInfo`는 implementation에 위임하지 않고 **proxy 자체에 직접 구현**되어 있다. `upgradeTo` 없이도 이 함수만큼은 정상 실행된다. 하지만 나머지 모든 비즈니스 로직은 implementation으로 위임되므로, `implementation() == 0x0` 상태면 전부 revert. `chainData()` 같은 조회 함수도 포함.

**L2-L1 flow Pitfall #4와의 차이:** #4는 upgradeTo 선행 없이 setSelectorImplementations2가 실패하는 케이스. #14는 upgradeTo 없이도 *일부 함수가 성공*하기 때문에 문제를 인지하기 더 어렵다.

**실제 사례(2026-04-10):** ect-defi `L2toL2CrossTradeProxy(0x2452ceB6...)`에 이전 세션에서 setChainInfo까지는 정상 실행됐지만 upgradeTo는 미실행. 이후 `chainData(chainId)` 호출 시 revert로 문제 발견.

**방지:**
- 배포 직후 `cast call <proxy> "implementation()"` 확인. `0x0`이면 `upgradeTo` 미실행.
- deploy 스크립트에서 upgradeTo 후 `implementation()` 반환값 어설션 추가.

**신뢰도:** HIGH (실제 발생 + 소스 코드 검증)

---

## 단계별 우선순위 요약

| 단계 | 관련 Pitfall | 우선순위 |
|------|-------------|---------|
| SDK: DeployCrossTradeLocal 구현 | #1, #2, #3 | MUST |
| SDK: 컨트랙트 주소 예측 | #2, #4 | MUST |
| SDK: Proxy 초기화 시퀀스 | #4, #9 | MUST |
| Backend: L1 setChainInfo | #5 | MUST |
| Backend: SDK 통합 | #6 | HIGH |
| Backend: 토큰 등록 | #10 | HIGH |
| Platform: dApp 컨테이너 | #8 | MEDIUM |
| SDK: L1 nonce 관리 | #11 | MEDIUM |
| SDK: L2toL2 ABI 차이 | #13 | MEDIUM |

---

*Source: `.planning/research/PITFALLS.md` (2026-04-07)*
