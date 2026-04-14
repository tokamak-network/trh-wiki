---
updated: 2026-04-15
sources:
  - raw/architecture/tech-stack.md
related:
  - "[[trh-platform]]"
  - "[[trh-platform-ui]]"
  - "[[trh-backend]]"
  - "[[testing]]"
  - "[[l2-deploy-local]]"
tags: [workflow]
---

# Local Development Environment

TRH Platform 생태계의 로컬 개발 환경 설정 가이드. 각 레포는 독립적으로 개발 서버를 띄울 수 있다.

---

## 사전 요구사항

| 항목 | 버전 |
|------|------|
| Node.js | 20.x |
| Go | 1.24 |
| Docker Desktop | 최신 (로컬 L2 배포 시 필수) |
| Foundry | 최신 (`forge`, `cast`, `anvil`) |

---

## trh-platform (Electron)

```bash
cd trh-platform
npm install
npm run dev          # Electron + Vite dev server 동시 기동
```

### 핵심 환경 변수

| 변수 | 용도 |
|------|------|
| `VITE_MOCK_ELECTRON=true` | Electron 없이 브라우저에서 렌더러(React) 단독 테스트 |
| `ELECTRON_USE_BUILD=1` | Vite dev server 대신 빌드 결과물 사용 (E2E 테스트용) |

`VITE_MOCK_ELECTRON=true`를 사용하면 `window.electronAPI`를 mock으로 대체해 브라우저만으로 UI 개발이 가능하다.

---

## trh-platform-ui (Next.js)

```bash
cd trh-platform-ui
npm install
npm run dev          # localhost:3000
```

### 핵심 환경 변수

| 변수 | 기본값 | 용도 |
|------|--------|------|
| `NEXT_PUBLIC_API_BASE_URL` | `http://localhost:8000` | trh-backend 연결 |

개발 시 **MSW**(Mock Service Worker)로 API 응답을 모킹할 수 있다 (`msw` 2.12.14).

Swagger UI로 API 탐색: `http://localhost:8000/swagger/index.html`

---

## trh-backend (Go)

```bash
cd trh-backend
# PostgreSQL 실행 (Docker)
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:15

go run main.go       # localhost:8000
```

AutoMigrate가 시작 시 자동 실행되므로 별도 마이그레이션 명령 불필요.

---

## trh-sdk (Go)

CLI 도구이므로 직접 개발 서버는 없다.

```bash
cd trh-sdk
go build -o trh .   # 로컬 바이너리 빌드
./trh --help
```

---

## 로컬 L2 배포 테스트

전체 로컬 L2 배포 워크플로우 → [[l2-deploy-local]]

테스트 실행 방법 → [[testing]]
