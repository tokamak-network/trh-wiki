---
updated: 2026-04-09
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

---

## 환경 변수

- `VITE_MOCK_ELECTRON=true` — Electron 없이 브라우저에서 렌더러 테스트
- `ELECTRON_USE_BUILD=1` — Vite dev server 대신 빌드 결과물 사용 (E2E 테스트 시)
