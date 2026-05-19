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

trh-sdk `[deployer] Step N/M` 로그 기반으로 검증된 step별 substep 수.

```ts
const STEP_SUBSTEP_TOTAL: Record<string, number> = {
  'deploy-l1-contracts': 35,  // tokamak-deployer deploy-contracts subcommand
  'deploy-aws-infra': 16,     // FP Path Stage B — steps 15-16은 anchor state tail 커버
  'deploy-local-infra': 7,    // non-FP local Docker preset
};
```

**주의사항**:
- `deploy-l1-contracts`의 35는 tokamak-deployer가 emit하는 별도 시퀀스로, trh-sdk Stage B와 무관하다.
- `deploy-aws-infra` FP Path: Stage B step 수는 **16** (2026-05-13 변경, 이전: 15). steps 15-16이 ~19분 tail 커버.
  - Step 15: "Waiting for L2 genesis block" — op-geth ALB health + 기동 대기 (최대 3600×5s retry)
  - Step 16: "Submitting anchor state to L1" — Guard A(idempotency), Guard B(simulation), L1 tx + WaitMined
- integration steps는 `step N/M` 패턴 없음 → 제외 (velocity 측정 불가)

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

---

## Phase Timeline (Deployments Tab)

### 개요

`DeploymentsTab` 상단에 배포 세션별 소요 시간 내역을 표시하는 카드 그룹.
기존 flat 테이블(스텝별 행 나열)을 보완하며, 하나의 배포 세션에서 각 스텝이 얼마나 걸렸는지 한눈에 확인 가능.

`deploy-aws-infra` 스텝의 경우 내부 로그를 파싱해 4개 하위 단계로 세분화:
- **EKS / VPC / EFS** — Stage A 완료까지
- **K8s / Helm** — Stage B 시작 → Helm 설치 완료까지
- **L1 Init & Anchor** — Helm 완료 → Preset 모듈 시작 (또는 step 종료)까지
- **Preset Modules** — 프리셋 모듈 설치 구간

### 파일 구조

| 파일 | 역할 |
|------|------|
| `src/features/rollup/components/detail/PhaseTimeline.tsx` | UI 컴포넌트 (`PhaseTimeline`, `SessionCard`, `AwsInfraSubPhases`) |
| `src/features/rollup/utils/sessionGrouping.ts` | 배포 행을 시간 간격 기준으로 세션 그룹화 |
| `src/features/rollup/utils/phaseTimings.ts` | deploy-aws-infra 로그에서 phase 경계 타임스탬프 추출 |

### 세션 그룹화 (`groupIntoSessions`)

ThanosDeployment[] 배열을 시간 간격으로 묶어 `DeploymentSession[]` 반환 (최신 세션 먼저).

**알고리즘**: started_at 기준 ASC 정렬 → `sessionEndMs = max(finished_at)` 추적 → 다음 행의 `started_at > sessionEndMs + 5min`이면 새 세션.

**설계 이유**: 병렬 실행 스텝(deploy-l1-contracts + deploy-aws-infra)이 동일 세션 내에 속하려면 단순 인접 비교가 아닌 세션 전체 끝 시간과 비교해야 한다.

### Phase 경계 추출 (`extractAwsInfraPhases`)

deploy-aws-infra 로그(ASC 순)를 한 번 스캔하여 각 경계의 첫 번째 등장 타임스탬프를 반환.

| 경계 | 패턴 |
|------|------|
| `stageAStart` | `Deploying Stage A AWS infrastructure` |
| `stageBStart` | `Deploying Thanos stack infrastructure.*Stage B` |
| `k8sDone` | `Helm charts installed successfully` |
| `presetStart` | `Installing preset modules` |

JSON 래핑(`{msg: ...}`) + ANSI 이스케이프 자동 제거. 패턴 미발견 시 `null` (graceful degradation — 해당 하위 행 미표시).

### 컴포넌트 설계 (무한 루프 방지)

**잘못된 패턴**: 자식 컴포넌트가 로그 로드 완료 시 `onPhases` 콜백으로 부모 state를 업데이트 → `useEffect([logs, onPhases])` → 부모 리렌더 → 새 콜백 참조 → 무한 루프.

**채택된 패턴**: `AwsInfraSubPhases`가 `useThanosDeploymentLogsQuery` + `useMemo(() => extractAwsInfraPhases(logs), [logs])`로 완전 자립. 부모로 state를 절대 push하지 않는다.

로그는 `refetchIntervalMs: false`로 1회만 fetch (completed step 대상, 변경 없음).
