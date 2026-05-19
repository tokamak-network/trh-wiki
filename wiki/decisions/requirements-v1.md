---
updated: 2026-04-09
source: raw/decisions/requirements-v1.md
sources: []
related:
  - "[[trh-platform]]"
  - "[[cross-trade]]"
  - "[[l2-deploy-local]]"
tags: [decision]
---


# Requirements v1 — CrossTrade Integration

CrossTrade TRH 통합 프로젝트의 v1 요구사항 30개. DeFi/Full Preset 선택 시 CrossTrade 자동 배포 및 7일 출금 대기 없는 크로스체인 토큰 교환 제공.

**관련:** [[trh-platform]], [[cross-trade]], [[l2-deploy-local]]

**정의:** 2026-04-07 | **상태:** Phase 1~4 완료, Phase 5 E2E 실행 중

---

## SDK — L1 Deposit Tx 배포

| ID | 요구사항 | Phase | 상태 |
|----|---------|-------|------|
| SDK-01 | `DeployCrossTradeLocal()`이 L1 `OptimismPortal.depositTransaction()`을 통해 L2CrossTrade(impl) 생성 | Phase 1 | ✅ |
| SDK-02 | L2CrossTradeProxy 생성, ADMIN_ROLE이 deployer에게 부여 | Phase 1 | ✅ |
| SDK-03 | `setSelectorImplementations2()` → `initialize()` → `setChainInfo()` → `registerToken()` 6-step 실행 | Phase 1 | ✅ |
| SDK-04 | L2toL2CrossTradeL2(impl) + L2toL2CrossTradeProxy 동일 6-step으로 배포 | Phase 1 | ✅ |
| SDK-05 | OptimismPortal ABI 바인딩이 abigen으로 생성되어 Go에서 사용 가능 | Phase 1 | ✅ |
| SDK-06 | 각 L1 Deposit Tx의 L2 receipt 확인으로 배포 성공 여부 검증 | Phase 1 | ✅ |
| SDK-07 | `DeployCrossTradeLocalOutput`이 4개 컨트랙트 주소를 정확히 반환 | Phase 1 | ✅ |

---

## SDK — Preset 설정

| ID | 요구사항 | Phase | 상태 |
|----|---------|-------|------|
| SDK-08 | DeFi preset에 `crossTrade=true` | Phase 2 | ✅ |
| SDK-09 | Gaming preset에서 `crossTrade` 제거 | Phase 2 | ✅ |
| SDK-10 | Full preset에 `crossTrade=true` 유지 | Phase 2 | ✅ |

---

## Backend — 로컬 배포 언블록

| ID | 요구사항 | Phase | 상태 |
|----|---------|-------|------|
| BE-01 | `localUnsupported` 맵에서 crossTrade 항목 제거 | Phase 2 | ✅ |
| BE-02 | DeFi/Full preset 로컬 배포 시 CrossTrade integration entity 생성 | Phase 2 | ✅ |

---

## Backend — Auto-Install 파이프라인

| ID | 요구사항 | Phase | 상태 |
|----|---------|-------|------|
| BE-03 | CrossTrade 활성 preset 시 `DeployCrossTradeLocal()` 호출 | Phase 3 | ✅ |
| BE-04 | SDK 완료 후 `L1CrossTradeProxy.setChainInfo()` 호출 (L2→L1) | Phase 3 | ✅ |
| BE-05 | SDK 완료 후 `L2toL2CrossTradeL1.setChainInfo()` 호출 (L2→L2) | Phase 3 | ✅ |
| BE-06 | `setChainInfo` 실패 시 최대 3회 재시도 | Phase 3 | ✅ |
| BE-07 | `config/.env.crosstrade` 자동 생성으로 dApp 환경 변수 설정 | Phase 3 | ✅ |
| BE-08 | CrossTrade dApp Docker 컨테이너 시작 | Phase 3 | ✅ |
| BE-09 | integration metadata에 컨트랙트 주소와 dApp URL 저장 | Phase 3 | ✅ |
| BE-10 | `CrossTradePresetConfig` 구조체: L1 주소, owner key, 토큰 쌍 포함 | Phase 3 | ✅ |
| BE-11 | `CrossTradeL1RegistrationInput/Output` 구조체 정의 | Phase 3 | ✅ |

---

## Platform — Docker Compose

| ID | 요구사항 | Phase | 상태 |
|----|---------|-------|------|
| PLT-01 | docker-compose에 CrossTrade dApp 서비스 정의 (port 3004) | Phase 4 | ✅ |
| PLT-02 | CrossTrade dApp은 DeFi/Full preset에서만 시작 | Phase 4 | ✅ |

---

## Platform UI — Preset & 상태

| ID | 요구사항 | Phase | 상태 |
|----|---------|-------|------|
| UI-01 | `preset.ts` DeFi preset의 `crossTrade: true` | Phase 4 | ✅ |
| UI-02 | `preset.ts` Gaming preset의 `crossTrade: false` | Phase 4 | ✅ |
| UI-03 | Rollup Detail Components 탭에 CrossTrade 상태 카드 표시 | Phase 4 | ✅ |
| UI-04 | CrossTrade 상태 카드에 dApp URL 링크 (http://localhost:3004) 포함 | Phase 4 | ✅ |

---

## E2E 검증

| ID | 요구사항 | Phase | 상태 |
|----|---------|-------|------|
| E2E-01 | Sepolia에서 DeFi preset 배포 후 CrossTrade L2 컨트랙트 4개 정상 배포 | Phase 5 | ✅ |
| E2E-02 | L1 `setChainInfo` 성공적 호출, CrossTrade 사용 가능 상태 확인 | Phase 5 | ✅ |
| E2E-03 | CrossTrade dApp이 http://localhost:3004에서 접근 가능 | Phase 5 | ✅ |

---

## v2 요구사항 (연기)

현재 로드맵에 미포함. 향후 릴리즈 트래킹.

| ID | 기능 | 카테고리 |
|----|------|---------|
| TOK-01 | USDC 토큰 쌍 사전 등록 + 전용 USDC 브릿지 연동 | Token Support |
| TOK-02 | USDT 토큰 쌍 + double approval 패턴 처리 | Token Support |
| TOK-03 | L2→L2 크로스트레이드 E2E 테스트 | Token Support |
| UX-01 | ConfigReview 단계에 CrossTrade 정보 read-only 표시 | UX Polish |
| UX-02 | L1 Deposit Tx 진행률 표시 (12단계 중 N단계) | UX Polish |
| UX-03 | setChainInfo 실패 에러 복구 플로우 UI | UX Polish |
| INFRA-01 | EC2 보안 그룹에 CrossTrade dApp 포트(3004) 추가 | Infrastructure |
| INFRA-02 | deployer/owner 키 분리 (프로덕션용) | Infrastructure |

---

## 스코프 외

| 기능 | 제외 이유 |
|------|---------|
| AWS/K8s CrossTrade 배포 수정 | 기존 Foundry 스크립트 유지, 로컬 전용 스코프 |
| Genesis Predeploy 방식 | constructor 미실행, bridge invariant 위반으로 폐기 |
| 메인넷 배포 | Sepolia 테스트넷 스코프 |
| 기존 `cross_trade.go` 수정 | 새 함수로 병존 원칙 |
| Magic link/OAuth 인증 | 프로젝트 범위 외 |

---

*Source: `.planning/REQUIREMENTS.md` (2026-04-07)*
