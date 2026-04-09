# Requirements: CrossTrade TRH Integration

**Defined:** 2026-04-07
**Core Value:** DeFi/Full Preset 선택만으로 CrossTrade가 자동 배포되어 7일 출금 대기 없는 빠른 크로스체인 토큰 교환 제공

## v1 Requirements

Requirements for Phase 1 (Foundation) release. Each maps to roadmap phases.

### SDK — L1 Deposit Tx Deployment

- [x] **SDK-01**: DeployCrossTradeLocal() 함수가 L1 OptimismPortal.depositTransaction()을 통해 L2CrossTrade(impl) 컨트랙트를 생성할 수 있다
- [x] **SDK-02**: DeployCrossTradeLocal() 함수가 L2CrossTradeProxy 컨트랙트를 생성하고 ADMIN_ROLE이 deployer에게 부여된다
- [x] **SDK-03**: DeployCrossTradeLocal() 함수가 proxy.setSelectorImplementations2()로 impl 연결, initialize()로 CrossDomainMessenger 설정, setChainInfo()로 L1 연결, registerToken()으로 ETH 토큰 쌍을 등록할 수 있다
- [x] **SDK-04**: DeployCrossTradeLocal() 함수가 L2toL2CrossTradeL2(impl) + L2toL2CrossTradeProxy도 동일한 6-step으로 배포할 수 있다
- [x] **SDK-05**: OptimismPortal ABI 바인딩이 abigen으로 생성되어 Go 코드에서 사용 가능하다
- [x] **SDK-06**: 각 L1 Deposit Tx의 L2 receipt를 확인하여 배포 성공 여부를 검증한다
- [x] **SDK-07**: DeployCrossTradeLocalOutput 구조체가 배포된 4개 컨트랙트 주소를 정확히 반환한다

### SDK — Preset Configuration

- [x] **SDK-08**: PresetModules에서 DeFi preset에 crossTrade=true가 설정된다
- [x] **SDK-09**: PresetModules에서 Gaming preset에서 crossTrade가 제거된다
- [x] **SDK-10**: PresetModules에서 Full preset에 crossTrade=true가 유지된다

### Backend — Local Deployment Unblock

- [x] **BE-01**: stack_lifecycle.go의 localUnsupported 맵에서 crossTrade 항목이 제거된다
- [x] **BE-02**: 로컬 infra에서 DeFi/Full preset 배포 시 CrossTrade integration entity가 생성된다

### Backend — Auto-Install Pipeline

- [x] **BE-03**: deployment.go의 로컬 auto-install 블록에서 CrossTrade가 활성화된 preset일 때 SDK의 DeployCrossTradeLocal()을 호출한다
- [x] **BE-04**: SDK 배포 완료 후 L1 CrossTradeProxy.setChainInfo()를 호출하여 새 L2를 등록한다 (L2→L1)
- [x] **BE-05**: SDK 배포 완료 후 L2toL2CrossTradeL1.setChainInfo()를 호출하여 새 L2를 등록한다 (L2→L2)
- [x] **BE-06**: setChainInfo 실패 시 최대 3회 재시도한다
- [x] **BE-07**: config/.env.crosstrade 파일을 자동 생성하여 dApp 환경 변수를 설정한다
- [x] **BE-08**: CrossTrade dApp Docker 컨테이너를 시작한다
- [x] **BE-09**: integration metadata에 배포된 컨트랙트 주소와 dApp URL을 저장한다

### Backend — DTO

- [x] **BE-10**: CrossTradePresetConfig 구조체가 L1 CrossTrade 주소, owner key, 토큰 쌍을 포함한다
- [x] **BE-11**: cross_trade_local.go에 CrossTradeL1RegistrationInput/Output 구조체가 정의된다

### Platform — Docker Compose

- [x] **PLT-01**: docker-compose에 CrossTrade dApp 서비스가 정의된다 (tokamaknetwork/cross-trade-app, port 3004)
- [x] **PLT-02**: CrossTrade dApp 서비스는 DeFi/Full preset에서만 시작된다

### Platform UI — Preset & Status

- [x] **UI-01**: preset.ts에서 DeFi preset의 crossTrade 모듈이 true로 설정된다
- [x] **UI-02**: preset.ts에서 Gaming preset의 crossTrade 모듈이 false로 설정된다
- [x] **UI-03**: Rollup Detail의 Components 탭에 CrossTrade integration 상태 카드가 표시된다
- [x] **UI-04**: CrossTrade 상태 카드에 dApp URL 링크(http://localhost:3004)가 포함된다

### E2E Verification

- [x] **E2E-01**: Sepolia 테스트넷에서 DeFi preset으로 L2 배포 후 CrossTrade L2 컨트랙트 4개가 정상 배포된다
- [x] **E2E-02**: L1 setChainInfo가 성공적으로 호출되어 CrossTrade 사용 가능 상태가 된다
- [x] **E2E-03**: CrossTrade dApp이 http://localhost:3004에서 접근 가능하다

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Token Support (Phase 2)

- **TOK-01**: USDC 토큰 쌍 사전 등록 및 전용 USDC 브릿지 연동
- **TOK-02**: USDT 토큰 쌍 사전 등록 및 double approval 패턴 처리
- **TOK-03**: L2→L2 크로스트레이드 E2E 테스트

### UX Polish (Phase 3)

- **UX-01**: ConfigReview 단계에 CrossTrade 정보 read-only 표시
- **UX-02**: L1 Deposit Tx 진행률 표시 (12단계 중 N단계 완료)
- **UX-03**: setChainInfo 실패 에러 복구 플로우 UI

### Infrastructure

- **INFRA-01**: EC2 보안 그룹에 CrossTrade dApp 포트(3004) 추가
- **INFRA-02**: deployer/owner 키 분리 (프로덕션용)

## Out of Scope

| Feature | Reason |
|---------|--------|
| AWS/K8s CrossTrade 배포 수정 | 기존 Foundry 스크립트 방식 유지, 로컬 전용 스코프 |
| Genesis Predeploy 방식 | constructor 미실행, bridge invariant 위반으로 폐기 |
| 메인넷 배포 | Sepolia 테스트넷 스코프 |
| 기존 cross_trade.go 수정 | 새 함수로 병존 원칙 |
| Magic link/OAuth 인증 | 프로젝트 범위 외 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SDK-01 | Phase 1 | Complete |
| SDK-02 | Phase 1 | Complete |
| SDK-03 | Phase 1 | Complete |
| SDK-04 | Phase 1 | Complete |
| SDK-05 | Phase 1 | Complete |
| SDK-06 | Phase 1 | Complete |
| SDK-07 | Phase 1 | Complete |
| SDK-08 | Phase 2 | Complete |
| SDK-09 | Phase 2 | Complete |
| SDK-10 | Phase 2 | Complete |
| BE-01 | Phase 2 | Complete |
| BE-02 | Phase 2 | Complete |
| BE-03 | Phase 3 | Complete |
| BE-04 | Phase 3 | Complete |
| BE-05 | Phase 3 | Complete |
| BE-06 | Phase 3 | Complete |
| BE-07 | Phase 3 | Complete |
| BE-08 | Phase 3 | Complete |
| BE-09 | Phase 3 | Complete |
| BE-10 | Phase 3 | Complete |
| BE-11 | Phase 3 | Complete |
| PLT-01 | Phase 4 | Complete |
| PLT-02 | Phase 4 | Complete |
| UI-01 | Phase 4 | Complete |
| UI-02 | Phase 4 | Complete |
| UI-03 | Phase 4 | Complete |
| UI-04 | Phase 4 | Complete |
| E2E-01 | Phase 5 | Complete |
| E2E-02 | Phase 5 | Complete |
| E2E-03 | Phase 5 | Complete |

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 30
- Unmapped: 0

---
*Requirements defined: 2026-04-07*
*Last updated: 2026-04-07 after roadmap creation*
