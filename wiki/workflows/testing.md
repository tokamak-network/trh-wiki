---
updated: 2026-04-09
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
│   ├── preset-wizard.spec.ts     # MSW 모드 preset 선택 플로우
│   ├── electron-*.live.spec.ts   # Electron + 실제 서비스
│   └── matrix/run-matrix.sh      # 4개 preset 매트릭스 스크립트
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

*Source: `.planning/codebase/TESTING.md` (2026-04-09)*
