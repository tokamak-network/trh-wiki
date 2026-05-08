---
updated: 2026-04-15
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

**표시 내용**:
- 전체 wall-clock elapsed (`Hh Mm Ss`)
- 현재 실행 중인 step pill badges (예: "L1 Contracts · AWS Infrastructure")

### durationUtils

`formatDuration(start?, end?, now?)` 함수를 `src/features/rollup/utils/durationUtils.ts`로 추출.
`DeploymentsTab`과 `DeploymentProgressCard` 모두 이 함수를 공유한다.
