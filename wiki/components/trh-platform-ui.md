---
updated: 2026-05-09
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

AWS 인프라 배포(`deploy-aws-infra`)와 L1 컨트랙트 배포(`deploy-l1-contracts`)는 백엔드에서 병렬 실행된다 (`executeDeploymentsAWSParallel`). 기존 `DeploymentsTab`은 각 row 별 독립 elapsed time만 표시했기 때문에, 전체 wall-clock 시간을 한눈에 알 수 없었다.

### DeploymentProgressCard

**위치**: `src/features/rollup/components/detail/DeploymentProgressCard.tsx`

OverviewTab 상단에 자동 표시되는 카드. 활성 deployment(`InProgress | Pending`)가 없으면 `null` 반환 (카드 자체가 사라짐).

**Wall-clock 계산**:
- `min(started_at)` of active rows → `now` (1초 tick)
- 완료 후엔 카드가 숨겨짐 (MVP)

**표시 내용** (2026-05-09 업데이트):
- 전체 wall-clock elapsed (`Hh Mm Ss`)
- 활성 deployment마다 `ActiveStepProgress` 컴포넌트 (`flex-col gap-4`)

### ActiveStepProgress

**위치**: `src/features/rollup/components/detail/ActiveStepProgress.tsx`

`ActiveStepPill`을 대체하는 컴포넌트. 배포 진행 상황을 풍부하게 표시하고 로그 다이얼로그를 연다.

**표시 내용**:
- Step 이름 (`getStepShortName`)
- 진행 바: `extractStepProgress(logs)` → `Step X / Y (N%)` 파싱 성공 시 표시
- 정상 상태: `extractCurrentSubtask(logs)` 현재 subtask 레이블
- 에러 상태: 첫 번째 error 로그 텍스트 + 빨간 버튼
- `[Logs →]` 버튼: 해당 deployment의 `LogDialog` 열기

**데이터 패치**: `useThanosDeploymentLogsQuery(deployment.stack_id, deployment.id, { limit: 100, refetchIntervalMs: 5000 })`

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
