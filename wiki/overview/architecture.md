---
updated: 2026-04-09
sources:
  - raw/architecture/tech-stack.md
related:
  - "[[trh-platform]]"
  - "[[trh-sdk]]"
  - "[[trh-backend]]"
  - "[[trh-platform-ui]]"
  - "[[presets]]"
  - "[[l2-deployment]]"
tags: [overview]
---

# TRH Platform Architecture

TRH Platform은 L2 롤업 체인을 배포·운영하기 위한 4개 저장소로 구성된 풀스택 시스템이다.

---

## Repository Map

| Repository | Language | Role |
|------------|----------|------|
| [[trh-platform]] | TypeScript | Electron 데스크톱 앱 — 셸, 키 관리, AWS 인증 |
| [[trh-sdk]] | Go 1.24 | CLI 배포 엔진 — L1 컨트랙트, L2 노드, 모듈 오케스트레이션 |
| [[trh-backend]] | Go 1.24 | REST API 서버 — Gin + GORM, 태스크 관리, RBAC |
| [[trh-platform-ui]] | TypeScript | Next.js 웹 프론트엔드 — 배포 위자드, 대시보드 |

## Data Flow

```
trh-platform (Electron)
    │  Desktop shell, keystore, AWS SSO
    │  launches WebContentsView
    ▼
trh-platform-ui (Next.js, port 3000)
    │  Deployment wizard, stack dashboard
    │  REST API calls
    ▼
trh-backend (Gin API, port 8000)
    │  Auth/RBAC, task queue, stack lifecycle
    │  Go import
    ▼
trh-sdk (Go CLI)
    │  L1 contract deploy, L2 node start
    │  Docker Compose / AWS infra
    ▼
PostgreSQL (port 5432)
```

**핵심**: trh-platform-ui는 독립 웹앱이지만, 프로덕션에서는 trh-platform Electron 앱의 `WebContentsView`에 임베딩되어 실행된다. 이 구조 덕분에 Electron이 키스토어·AWS 자격증명을 webview에 주입할 수 있다.

---

## Shared Technology

| 기술 | platform | sdk | backend | ui |
|-----|:--------:|:---:|:-------:|:--:|
| TypeScript | ✅ | - | - | ✅ |
| Go | - | ✅ | ✅ | - |
| go-ethereum | - | ✅ | ✅ | - |
| ethers.js | ✅ | - | - | ✅ |
| AWS SDK | ✅ | ✅ | ✅ | - |
| BIP39/BIP32 | ✅ | ✅ | ✅ | ✅ |
| Docker | ✅ | ✅ | ✅ | - |
| Zod | ✅ | - | - | ✅ |
| PostgreSQL | - | - | ✅ | - |
| Terraform | - | ✅ | - | - |

---

## Deployment Targets

- **local** — Docker Compose on developer machine (Sepolia L1 + local L2 nodes)
- **ec2** — AWS EC2 via Terraform (Sepolia or Mainnet)

자세한 내용 → [[l2-deploy-local]], [[ec2-deploy]]

---

## L2 Preset System

4가지 preset이 L2 구성을 결정한다 → [[presets]]
