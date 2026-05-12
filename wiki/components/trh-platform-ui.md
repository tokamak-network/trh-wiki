---
updated: 2026-05-12
sources:
  - raw/architecture/tech-stack.md
related:
  - "[[architecture]]"
  - "[[trh-platform]]"
  - "[[trh-backend]]"
  - "[[presets]]"
  - "[[l2-deploy-local]]"
tags: [component]
---

# trh-platform-ui

Next.js 15.5 (App Router) 기반 웹 프론트엔드. trh-platform Electron 앱의 `WebContentsView`에 임베딩되어 실행된다.

---

## 핵심 역할

- L2 롤업 배포 위자드 (Preset 선택 → Basic Info → Config Review → 배포)
- 스택 대시보드 (배포 진행 상황, 체인 정보, 로그 스트리밍)
- Funding Status 표시 (Admin/Batcher/Proposer 잔액 확인)
- trh-backend REST API 연동

---

## 기술 스택

| 항목 | 버전 |
|------|------|
| Next.js | 15.5.9 (App Router) |
| React | 19.2.3 |
| TypeScript | 5.x |
| Tailwind CSS | v4 |
| shadcn/ui + Radix UI | - |
| TanStack React Query | 5.90.12 |
| react-hook-form + zod | 7.60.0 / 4.0.5 |
| axios | 1.10.0 |
| ethers | 6.x |

---

## 배포 위자드 플로우

### Preset Mode (2-step, 권장)

```
Step 1: Preset 선택
    General | DeFi | Gaming | Full
    → 선택 시 서비스 상세 패널(ServicePanel) 표시
Step 2: Basic Info & Deploy
    Chain Name (3-32자, lowercase/숫자/하이픈)
    Network: Mainnet / Testnet (Sepolia)
    AWS Access Key ID
    AWS Secret Access Key
    → "Deploy Rollup" 버튼으로 즉시 배포 요청
```

입력 5개 필드만 수집. Seed Phrase, L1 RPC URL, Beacon URL, Fee Token, Infra Provider 등은 시스템이 자동 결정.

### Classic Mode (4-step, 고급)

```
Step 1: Network & Chain 설정
Step 2: Account & AWS 설정 (Seed Phrase, L1 RPC URL 등)
Step 3: DAO Candidate (선택)
Step 4: Review & Deploy
```

→ Local Docker 관련 검증 항목: [[l2-deploy-local]]

---

## API 연동

- **Proxy**: `/api/proxy/` → Next.js middleware → trh-backend (port 8000)
- **Auth**: localStorage에 JWT 토큰 저장, Authorization: Bearer
- **State**: TanStack React Query로 서버 상태 관리
- **MSW**: 개발 시 API 모킹 (`msw` 2.12.14)

---

## 환경 변수

- `NEXT_PUBLIC_API_BASE_URL` — backend URL (Docker Compose에서 주입)
- `next-runtime-env` — 클라이언트 사이드 런타임 env var 지원

---

## Deployment Progress UI

### 배경

AWS 인프라 배포(`deploy-aws-infra`)와 L1 컨트랙트 배포(`deploy-l1-contracts`)는 백엔드에서 병렬 실행된다 (`executeDeploymentsAWSParallel`). 기존 카드는 활성 step별 독립 elapsed/ETA/progress를 표시하여 step 전환 시 카운터가 리셋되는 문제가 있었다.

### Phase-Level Metrics (2026-05-12 개선)

**핵심 변경**: step 단위 지표 → **phase 전체 기준** Elapsed / ETA / Progress%.

**Phase 분류**:
- `core` — `deploy-l1-contracts`, `deploy-aws-infra`, `deploy-local-infra`
- `integration` — `install-bridge`, `install-block-explorer`, `install-monitoring`, `install-drb`, `register-candidate`

각 phase는 독립 카드로 표시. core 완료 후 integration이 남으면 toast 알림 + integration 카드로 전환.

### DeploymentProgressCard

**위치**: `src/features/rollup/components/detail/DeploymentProgressCard.tsx`

OverviewTab 상단에 자동 표시. 활성 deployment(`InProgress | Pending`)가 없으면 `null` 반환.

내부에 `PhaseProgressCard` 컴포넌트를 렌더링. phase rows 분류, 1초 tick clock, core→integration 전환 toast 담당.

### PhaseProgressCard

**위치**: `DeploymentProgressCard.tsx` 내부 컴포넌트

phase 전체 기준 metrics를 계산·표시.

**데이터 패치**: 최대 2개 InProgress row(병렬 step 대응)의 로그를 각각 `useThanosDeploymentLogsQuery(stackId, deploymentId, { limit: 5000, refetchIntervalMs: 5000 })`로 fetch.

**표시 내용**:
- `[Elapsed]` — `now - min(phase rows' started_at)` (step 전환 시 리셋 없음)
- `[ETA]` — substep velocity 기반 잔여 시간 (데이터 부족 시 `—`)
- `[Progress %]` — `(완료 실측 + 현재 elapsed) / totalMs` (null 시 `—`)
- Secondary line — `Step N/M · step-name (substep N/M)` 또는 병렬 `Step N-M/Total · step1, step2`
- Progress bar + `[Logs →]` 버튼

### deploymentProgress.ts

**위치**: `src/features/rollup/utils/deploymentProgress.ts`

phase metrics를 계산하는 순수 함수 모음.

#### STEP_SUBSTEP_TOTAL

Go source에서 실제 검증된 step별 substep 수. **step N/M 로그를 emit하는 step만 포함** (나머지는 velocity 측정 불가):

```ts
const STEP_SUBSTEP_TOTAL: Record<string, number> = {
  'deploy-aws-infra': 18,   // Stage A(5) + Stage B(13, non-FP baseline)
  'deploy-local-infra': 7,  // non-FP baseline
};
```

- `deploy-l1-contracts`는 `step N/M` 로그 없음 → 제외
- integration steps도 해당 패턴 없음 → 제외

#### computeVelocity(logs)

로그 타임스탬프에서 substep/sec 속도를 측정.

```
velocity = (N_last - N_first) / (t_last - t_first)   [substeps/sec]
```

- window: 마지막 60초에 5개 이상 샘플이 있으면 60초 윈도우, 없으면 최근 5개 샘플 사용
- samples < 2 또는 dSubstep ≤ 0이면 `null` 반환
- JSON/ANSI 래핑 로그 자동 파싱

#### computePhaseMetrics(phaseRows, inProgressEntries, now)

```
elapsedMs = now - min(phaseRows.started_at)
completedActualMs = Σ (finished_at - started_at)  for completed rows
currentRemainingMs = max(per-InProgress-row remaining)
  → per-row remaining = (total - current) / velocity × 1000
  → 한 row라도 velocity null이면 전체 null (정직한 fallback)
pendingMs = Σ (STEP_SUBSTEP_TOTAL[step] / maxVelocity × 1000)  for Pending rows
  → 알 수 없는 step이 있으면 null
etaMs = currentRemainingMs + pendingMs   (어느 쪽이든 null이면 전체 null)
totalMs = completedActualMs + currentElapsedMs + etaMs
progress = min(1, (completedActualMs + currentElapsedMs) / totalMs)
```

**병렬 step 처리**: `deploy-l1-contracts`와 `deploy-aws-infra`는 동시에 InProgress일 수 있다. `max(remaining)` 사용 — 두 step이 모두 끝나야 phase가 진행된다.

**테스트**: `src/features/rollup/utils/__tests__/deploymentProgress.test.ts` — 14개 vitest.

### LogDialog (Progress Dashboard)

**위치**: `src/features/rollup/components/detail/LogDialog.tsx`

단순 로그 덤프에서 진행 상황 대시보드로 개선됨.

**Progress Panel** (상단 고정):
- Step 진행 바 (`extractStepProgress`)
- 현재 subtask 레이블 (`extractCurrentSubtask`)
- 에러 배너: 첫 번째 error 로그 텍스트 (존재 시만 표시)

**레벨 필터**: `ALL / ERROR / WARN / INFO` 배타적 토글 버튼. 기본 ALL.

**색상 코딩** (어두운 배경 기준):
- `error` → `text-red-400`
- `warn` → `text-yellow-300`
- `info` → `text-slate-300`
- `default` → `text-slate-500`

**Auto-scroll**:
- Realtime ON 시 → 새 로그 수신마다 최하단으로 스크롤
- `deployment.status === 'Failed'` 시 → 다이얼로그 오픈 후 150ms 뒤 첫 번째 error 라인으로 스크롤

기존 컨트롤(Realtime 토글, 라인 수 셀렉터, 새로고침 버튼) 유지.

### 로그 파싱 유틸리티

**`extractStepProgress`** (`deploymentSubtask.ts`):
- 로그 배열을 최신 순(역방향)으로 스캔
- `\bstep\s+(\d+)\s*/\s*(\d+)/i` 패턴 매치 → `{ current, total }` 반환
- 매치 없거나 total=0이면 `null`

**`classifyLogLevel`** (`logLevel.ts`):
- JSON 우선: `level`, `lvl` 필드에서 `error/warn/info` 추출
- fallback: plain text 키워드 스캔 (대소문자 무관)
  - error: `error:`, `ERROR`, `ERR `, `ERR:`, `failed`, `exception`
  - warn: `warn:`, `WARN`, `WARNING`
  - info: `info:`, `INFO`
- 반환 타입: `'error' | 'warn' | 'info' | 'default'`

### durationUtils

`formatDuration(start?, end?, now?)` 함수를 `src/features/rollup/utils/durationUtils.ts`로 추출.
`DeploymentsTab`과 `DeploymentProgressCard` 모두 이 함수를 공유한다.
