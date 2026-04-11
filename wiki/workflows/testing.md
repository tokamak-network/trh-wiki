---
updated: 2026-04-11
source: raw/architecture/testing-guide.md
---

# Testing Strategy

trh-platform의 테스트 구조, 실행 방법, 패턴 가이드.

**관련:** [[trh-platform]], [[l2-deploy-local]]

---

## 테스트 스택

| 레이어 | 도구 | 용도 |
|--------|------|------|
| Unit/Integration | Vitest 4.1.0 + happy-dom | React 컴포넌트, 모듈 함수, IPC 계약 |
| E2E (MSW) | Playwright + MSW | UI 로직, 백엔드 없이 |
| E2E (Electron) | Playwright Electron | 실제 Docker + 앱 전체 |
| Matrix | bash script | 4개 preset 순차 검증 |

---

## 실행 명령어

```bash
npm test                  # Unit/Integration (Vitest)
npm run test:watch        # 감시 모드
npm run test:e2e          # E2E (MSW 모드, port 3009)
npm run test:matrix       # 4개 preset 전체 E2E
npm run test:matrix:full  # 펀딩 + 배포 + 검증 포함 전체 사이클
npm run preflight         # sync-fixtures + test + test:e2e (커밋 전 검증)
```

---

## 테스트 파일 구조

```
tests/
├── unit/                     # 통합 테스트 (real modules, mocked externals)
│   ├── preset-config.test.ts     # Preset 스키마 검증
│   ├── docker-stack.test.ts      # docker-compose.yml 구조
│   ├── ipc-channels.test.ts      # IPC handler/invoke 쌍 검증
│   ├── deploy-local.test.ts      # 로컬 배포 플로우
│   └── funding-flow.test.ts      # 펀딩 트랜잭션 시퀀싱
├── e2e/                      # Playwright E2E
│   ├── preset-wizard.spec.ts         # MSW 모드 preset 선택 플로우
│   ├── electron-*.live.spec.ts       # Electron + 실제 서비스
│   ├── crosstrade-tx.live.spec.ts    # CrossTrade 실거래 트랜잭션 (CRT-01~07)
│   └── matrix/run-matrix.sh          # 4개 preset 매트릭스 스크립트
├── helpers/
│   ├── load-fixtures.ts          # tests/fixtures/에서 preset 데이터 로드
│   └── load-compose.ts           # docker-compose.yml 파싱
├── schemas/                  # Zod 스키마
│   ├── preset.schema.ts
│   └── docker-compose.schema.ts
└── fixtures/
    └── presets.json          # npm run sync-fixtures로 동기화
```

소스 co-located 테스트:
- `src/renderer/pages/SetupPage.test.tsx` — React 컴포넌트
- `src/main/aws-auth.test.ts` — Electron main process

---

## E2E 테스트 3가지 모드

### MSW 모드 (모의 백엔드)
- 명령어: `npm run test:e2e`
- Port: 3009 (`NEXT_PUBLIC_MSW=true`)
- 용도: UI 로직, 백엔드 없이 빠른 검증

### Live 모드 (실제 서비스)
- 조건: `make up` 실행 + Docker 서비스 가동
- 파일: `*.live.spec.ts`
- 조건: Backend `http://localhost:8000` 접근 가능

### Electron 모드 (전체 앱)
- 파일: `electron-*.live.spec.ts`
- Config: `playwright.electron.config.ts`
- 특성: `fullyParallel: false` (Electron 싱글턴), timeout 30분

---

## 핵심 패턴

### vi.hoisted() — import 전 mock 설정
```typescript
const { mockElectronAPI } = vi.hoisted(() => {
  return { mockElectronAPI: { docker: { start: vi.fn() }, ... } };
});
(globalThis as any).electronAPI = mockElectronAPI;
```
컴포넌트가 import될 때 `window.electronAPI`가 이미 존재해야 하므로 hoisted 사용.

### Parametric 테스트
```typescript
// Vitest
it.each(['general', 'defi', 'gaming', 'full'] as const)(
  '%s passes schema',
  (presetId) => expect(() => schema.parse(presets[presetId])).not.toThrow()
);

// Playwright
for (const preset of PRESETS) {
  test(`preset ${preset.id}`, async ({ page }) => { ... });
}
```

### Async 패턴
```typescript
await waitFor(() => {
  expect(screen.getByText('text')).toBeInTheDocument();
}, { timeout: 10000 });
```

### 에러 테스트
```typescript
mockKeystore.store.mockRejectedValueOnce(new Error('Encryption failed'));
await user.click(screen.getByText('Save & Continue'));
await waitFor(() => expect(screen.getByText('Keystore Error')).toBeInTheDocument());
```

---

## Fixtures 동기화

```bash
npm run sync-fixtures       # tests/fixtures/presets.json 업데이트
npm run sync-fixtures:dry   # 변경사항 미리 보기
```

Backend 스키마 변경 시 반드시 실행. `preflight` 명령에 포함됨.

---

## Mock 원칙

**Mock 대상:**
- 외부 API (AWS SDK, Electron API, OS calls)
- CSS, asset imports
- child_process, fs

**Mock 금지:**
- 핵심 비즈니스 로직
- Zod 스키마 (실제 인스턴스 사용)
- 내부 모듈 의존성

---

## Coverage

최소 커버리지 강제 없음. 중요 경로 집중:
- Preset 정의 (스키마 검증)
- Docker 작업 (시작/중지/풀)
- IPC 계약 (handler/invoke 쌍)
- E2E 사용자 플로우

---

---

## CrossTrade Live TX 테스트 (CRT)

**파일:** `tests/e2e/crosstrade-tx.live.spec.ts`

**실행 조건:**
- DeFi 또는 Full preset 스택 배포 + CrossTrade 컨트랙트 통합 완료
- Sepolia L1 RPC 접근 가능 (`LIVE_L1_RPC_URL`)
- Admin 지갑에 L1(Sepolia)과 L2 모두 ETH 잔고 필요

**실행 명령어:**
```bash
LIVE_CHAIN_NAME=ect-defi-crosstrade \
LIVE_L1_RPC_URL=https://eth-sepolia... \
npx playwright test --config playwright.live.config.ts tests/e2e/crosstrade-tx.live.spec.ts
```

**테스트 ID:**

| ID | 플로우 | 검증 포인트 |
|----|--------|------------|
| CRT-01 | L1-L2: L2 `requestNonRegisteredToken` | `NonRequestCT` 또는 `RequestCT` 이벤트 emit |
| CRT-02 | L1-L2: L1 `provideCT` | `ProvideCT` 이벤트 emit (auto gas estimation) |
| CRT-03 | L1-L2: L2 claim 확인 | `ProviderClaimCT` 이벤트 폴링 (최대 20분) |
| CRT-04 | L2-L2: L2 `requestNonRegisteredToken` | `NonRequestCT` 또는 `RequestCT` 이벤트 emit |
| CRT-05 | L2-L2: L1 `provideCT` | `ProvideCT` 이벤트 emit (CDM 2회, ~800k gas) |
| CRT-06 | L2-L2: L2 claim 확인 | `ProviderClaimCT` 이벤트 폴링 (최대 20분) |
| CRT-07 | dApp UI 스크린샷 | EIP-6963 mock provider 주입 → 페이지 접근 가능 |

**타임아웃:** TX 2분, L1→L2 cross-domain message relay 최대 20분 (5초 간격 폴링).

### EIP-6963 Mock Provider 주입 (CRT-07)

dApp은 `window.ethereum` 대신 EIP-6963 `eip6963:announceProvider` 이벤트를 통해 지갑을 감지한다. Playwright에서 지갑 없이 dApp UI를 로드하려면 mock provider를 page context에 주입해야 한다:

```typescript
await page.addInitScript(() => {
  const mockProvider = {
    request: async ({ method }: { method: string }) => {
      if (method === 'eth_requestAccounts') return ['0x1234...'];
      if (method === 'eth_chainId') return '0x1';
      return null;
    },
    on: () => {},
    removeListener: () => {},
  };
  window.dispatchEvent(new CustomEvent('eip6963:announceProvider', {
    detail: { info: { uuid: 'mock', name: 'Mock Wallet', rdns: 'mock.wallet', icon: '' }, provider: mockProvider }
  }));
});
```

→ [[cross-trade]], [[l1-gas-limits]]

---

*Source: `.planning/codebase/TESTING.md` (2026-04-09), 추가 업데이트: 2026-04-11*
