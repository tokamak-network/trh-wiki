---
updated: 2026-04-15
sources:
  - raw/architecture/tech-stack.md
related:
  - "[[architecture]]"
  - "[[trh-platform-ui]]"
  - "[[trh-backend]]"
  - "[[keystore]]"
  - "[[docker-compose-lifecycle]]"
tags: [component]
---

# trh-platform

Electron 33 기반 데스크톱 앱. 사용자가 직접 설치·실행하는 진입점이다.

---

## 핵심 역할

1. **Desktop shell** — trh-platform-ui(Next.js)를 `WebContentsView`에 임베딩
2. **Keystore** — OS safeStorage로 시드 구문을 암호화 저장, BIP44로 키 파생
3. **AWS auth** — ~/.aws 프로파일 파싱, SSO OIDC 로그인, role assumption
4. **Docker lifecycle** — Docker Compose up/down/pull, 헬스 체크
5. **Network guard** — Electron session.webRequest 훅으로 외부 요청 차단
6. **Deployment watcher** — 배포 상태 폴링, OS + 인앱 알림 발송

---

## 프로세스 구조

```
Main Process (Node.js)           Renderer Process (React)
├── index.ts         ──IPC──▶   App.tsx
├── docker.ts                    ├── SetupPage.tsx
├── keystore.ts                  ├── ConfigPage.tsx
├── aws-auth.ts                  └── ...
├── network-guard.ts
├── webview.ts
└── preload.ts  ──contextBridge──▶ window.electronAPI
```

- **Main ↔ Renderer**: IPC(ipcMain/ipcRenderer) + contextBridge
- **Main ↔ WebContentsView**: webview-preload.ts, `window.__` 글로벌 주입

---

## 기술 스택

| 항목 | 버전 |
|------|------|
| Electron | 33.0.0 |
| React | 19.2.4 |
| TypeScript | 5.9.3 |
| Vite (renderer) | 7.3.1 |
| ethers | 6.13.4 |
| @aws-sdk/client-sso | 3.1013.0 |
| Vitest | 4.1.0 |
| Playwright | 1.58.2 |

---

## 빌드 타겟

| OS | 포맷 | 아키텍처 |
|----|------|---------|
| macOS | DMG | x64 + arm64 |
| Windows | NSIS | x64 |
| Linux | AppImage | x64 |

---

## 주요 모듈

- **[[keystore]]** — `src/main/keystore.ts`
- AWS auth — `src/main/aws-auth.ts` (SSO OIDC flow → [[ec2-deploy]])
- **[[docker-compose-lifecycle]]** — `src/main/docker.ts`
- Network Guard — `src/main/network-guard.ts`
- WebView — `src/main/webview.ts`
- **DeploymentWatcher** — `src/main/deployment-watcher.ts` (배포 상태 폴링 + 알림)
- **NotificationStore** — `src/main/notifications.ts` (인앱 알림 저장소)

---

## DeploymentWatcher

백엔드 API를 10초 간격으로 폴링하여 배포 상태 전환을 감지하고 알림을 발송한다.

### 감지하는 전환

| 이전 상태 | 새 상태 | 알림 |
|----------|---------|------|
| Deploying / Updating | Deployed | "L2 Deployment Complete" |
| Deploying / Updating | FailedToDeploy / FailedToUpdate | "L2 Deployment Failed" + 실패 원인 |
| InProgress | Completed | "Service Deployment Complete" |
| InProgress | Failed | "Service Deployment Failed" |

### 실패 원인 추출 흐름

`FailedToDeploy` / `FailedToUpdate` 감지 시 추가 API 호출로 실패 원인을 추출한다:

```
GET /api/v1/stacks/thanos/:stackId/deployments?limit=1
  └─ deploymentId 추출
     └─ GET /api/v1/stacks/thanos/:stackId/deployments/:id/logs?limit=50
        └─ JSON Lines 파싱: 마지막 level==="error" 항목의 message
           └─ NotificationStore.add({ ..., detail: reason })
```

- 로그는 JSON Lines 포맷 (`{"level":"error","message":"..."}`)
- 추출 우선순위: error level 마지막 줄 → 마지막 비어있지 않은 raw 줄 → undefined
- 로그 조회 실패 시에도 `detail` 없이 알림은 반드시 발송됨 (try-catch → undefined)

### AppNotification 인터페이스

```ts
interface AppNotification {
  id: string;
  type: 'image-update' | 'release-update' | 'system' | 'deployment';
  title: string;
  message: string;
  detail?: string;      // 배포 실패 원인 텍스트 (선택적)
  timestamp: number;
  read: boolean;
  actionLabel?: string;
  actionType?: 'update-containers';
}
```

`detail`은 `NotificationPage.tsx` 알림 카드에 모노스페이스 빨간 텍스트로 인라인 표시된다.

### 주의사항

- URL 패턴: `/api/v1/stacks/thanos/{stackId}/...` — "thanos" 세그먼트 필수
- `src/main/index.ts`에서 `app:load-platform` IPC 핸들러 내부에서 `start()` 호출
- `before-quit` 이벤트에서 `stop()` 호출
- 토큰이 없으면 폴링 사이클 전체 스킵 (`getCachedAuthToken()` 반환값 검사)

---

## 환경 변수

- `VITE_MOCK_ELECTRON=true` — Electron 없이 브라우저에서 렌더러 테스트
- `ELECTRON_USE_BUILD=1` — Vite dev server 대신 빌드 결과물 사용 (E2E 테스트 시)
