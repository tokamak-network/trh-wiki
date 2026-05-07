---
updated: 2026-04-09
sources:
  - raw/architecture/tech-stack.md
related:
  - "[[architecture]]"
  - "[[trh-sdk]]"
  - "[[trh-platform-ui]]"
  - "[[docker-compose-lifecycle]]"
tags: [component]
---

# trh-backend

Go 1.24 + Gin 1.10 기반 REST API 서버. trh-platform-ui의 API 요청을 받아 trh-sdk를 직접 호출(Go import)한다.

---

## 핵심 역할

- L2 스택 배포·종료 API 제공
- 비동기 태스크 큐 관리 (5-worker pool, PostgreSQL 영속화)
- JWT 기반 인증/RBAC (Admin / User)
- AWS 자격증명·RPC URL 설정 관리
- Docker socket을 통한 컨테이너 라이프사이클 관리

---

## API 구조

```
/api/v1
├── /auth                    — 로그인, 프로필, 사용자 관리
├── /configuration           — AWS 자격증명, RPC URL, API 키
├── /stacks                  — 스택 CRUD, 배포 시작/종료
├── /stacks/thanos           — Thanos preset 배포 전용
│   └── POST /preset-deploy  — infraProvider: "local" | "aws"
├── /tasks                   — 비동기 태스크 진행 상황
└── /health                  — 헬스 체크
```

Swagger UI: `/swagger/index.html`

---

## 기술 스택

| 항목 | 버전 |
|------|------|
| Go | 1.24 |
| Gin | 1.10.0 |
| GORM | 1.26.1 |
| PostgreSQL | 15 |
| golang-jwt/jwt | v5.2.2 |
| go-ethereum | 1.17.1 |
| trh-sdk | 1.0.5 (Go import) |
| zap | 1.27.0 |

---

## 아키텍처 패턴

```
Handler → Service → Repository → GORM → PostgreSQL
                ↓
            trh-sdk (Go import)
```

- **태스크 시스템**: 요청 수신 즉시 태스크 ID 반환 → 백그라운드 실행 → SSE/polling으로 진행 상황 스트리밍
- **Migration**: 시작 시 `AutoMigrate()` 자동 실행
- **서버**: 포트 8000, read/write timeout 120s, graceful shutdown 30s

---

## Docker 이미지 특징

멀티스테이지 빌드 (Ubuntu 24.04 base):
- Node.js 20.16.0 번들링 (Foundry forge/cast/anvil 포함)
- CGO disabled
- Docker Hub: `tokamaknetwork/trh-backend`

---

## 로컬 배포 시 핵심 파라미터

`POST /api/v1/stacks/thanos/preset-deploy`에서:
- `infraProvider: "local"` → AWS 없이 로컬 Docker Compose로 L2 실행
- `infraProvider: "aws"` → Terraform + EC2로 클라우드 배포
