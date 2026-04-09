# TRH Platform Technology Stack

TRH Platform을 구성하는 4개 저장소의 기술 스택 문서.

---

## Overview

| Repository | Language | Role | Framework |
|------------|----------|------|-----------|
| **trh-platform** | TypeScript | Electron 데스크톱 앱 | Electron 33 + React 19 + Vite 7 |
| **trh-sdk** | Go 1.24 | CLI / 배포 엔진 | urfave/cli v3 |
| **trh-backend** | Go 1.24 | REST API 서버 | Gin 1.10 + GORM 1.26 |
| **trh-platform-ui** | TypeScript | 웹 프론트엔드 | Next.js 15.5 + React 19 |

---

## 1. trh-platform (Electron Desktop App)

### Core

| Category | Technology | Version |
|----------|------------|---------|
| Runtime | Node.js | 18.0.0+ |
| Language | TypeScript | 5.9.3 |
| Desktop Framework | Electron | 33.0.0 |
| UI Framework | React | 19.2.4 |
| Build Tool | Vite | 7.3.1 |
| Packager | electron-builder | 25.1.8 |

### Key Dependencies

| Library | Version | Purpose |
|---------|---------|---------|
| ethers | 6.13.4 | Ethereum wallet / key derivation |
| @aws-sdk/client-sso | 3.1013.0 | AWS SSO authentication |
| @aws-sdk/client-sso-oidc | 3.1013.0 | AWS OIDC flow |
| zod | 4.3.6 | Schema validation |
| js-yaml | 4.1.1 | YAML parsing |

### Testing

| Framework | Version | Scope |
|-----------|---------|-------|
| Vitest | 4.1.0 | Unit / Component |
| Playwright | 1.58.2 | E2E |
| Testing Library (React) | 16.3.2 | Component helpers |
| happy-dom | 20.8.4 | DOM environment |
| jsdom | 29.0.1 | DOM environment (alt) |

### Build Targets

- macOS: DMG (x64 + arm64)
- Windows: NSIS (x64)
- Linux: AppImage (x64)

### TypeScript Configuration

- **Main process**: ES2020 / CommonJS → `dist/main/`
- **Renderer**: ESNext / ESModule → Vite bundled `dist/renderer/`
- Both: `strict: true`

---

## 2. trh-sdk (CLI & Deployment Engine)

### Core

| Category | Technology | Version |
|----------|------------|---------|
| Language | Go | 1.24.11 |
| CLI Framework | urfave/cli | v3.0.0-beta1 |
| Module | github.com/tokamak-network/trh-sdk | - |

### Blockchain & Crypto

| Library | Version | Purpose |
|---------|---------|---------|
| go-ethereum | 1.17.1 | Ethereum client |
| c-kzg-4844 | 2.1.6 | KZG polynomial commitments |
| go-bip32 | 1.0.0 | HD wallet derivation |
| go-bip39 | 1.1.0 | Mnemonic seed phrases |
| gnark-crypto | 0.18.1 | ZK proof cryptography |
| uint256 | 1.3.2 | 256-bit integers |

### Cloud & Infrastructure

| Library | Version | Purpose |
|---------|---------|---------|
| aws-sdk-go-v2 | 1.41.1 | AWS SDK (EC2, EFS, S3, DynamoDB, CloudWatch) |
| Terraform | 1.9.8 | Infrastructure as Code |
| Helm | 3.16.3 | Kubernetes package manager |
| kubectl | 1.31.4 | Kubernetes CLI |
| Docker | - | Container management |

### Observability

| Library | Version | Purpose |
|---------|---------|---------|
| zap | 1.27.0 | Structured logging |
| OpenTelemetry | - | Distributed tracing |
| prometheus/client_golang | 1.20.5 | Metrics |

### System & Utilities

| Library | Version | Purpose |
|---------|---------|---------|
| gopsutil | 3.21.11 | System/process info |
| creack/pty | 1.1.24 | Pseudo-terminal |
| go.socket.io | 0.1.1 | Socket.IO protocol |
| yaml.v3 | 3.0.1 | YAML parsing |

### Testing & CI

- **Test Framework**: Go built-in + testify v1.11.1
- **Linter**: golangci-lint v2.0.2 (govet, unused)
- **CI**: GitHub Actions (lint, test, Docker multi-arch build)
- **Docker Registry**: Docker Hub (`tokamaknetwork/trh-sdk`, linux/amd64 + arm64)

---

## 3. trh-backend (REST API Server)

### Core

| Category | Technology | Version |
|----------|------------|---------|
| Language | Go | 1.24.11 |
| Web Framework | Gin | 1.10.0 |
| ORM | GORM | 1.26.1 |
| Database | PostgreSQL | 15 |
| API Docs | Swagger (swag) | 1.16.4 |

### Authentication & Security

| Library | Version | Purpose |
|---------|---------|---------|
| golang-jwt/jwt | v5.2.2 | JWT authentication |
| golang.org/x/crypto | 0.45.0 | Cryptographic operations |

- Role-based access control (Admin / User)
- Bearer token in Authorization header

### API Structure

```
/api/v1
├── /auth           — Login, profile, user management
├── /configuration  — AWS credentials, RPC URLs, API keys
├── /stacks         — Stack lifecycle (deploy, terminate)
├── /stacks/thanos  — Thanos-specific operations
├── /tasks          — Async task progress tracking
└── /health         — Health check
```

- CORS: All origins, 12h preflight cache
- Swagger UI: `/swagger/index.html`

### Key Dependencies

| Library | Version | Purpose |
|---------|---------|---------|
| go-ethereum | 1.17.1 | Blockchain interaction |
| tokamak-network/trh-sdk | 1.0.5 | Rollup deployment SDK |
| aws-sdk-go-v2 | 1.41.1 | AWS services |
| zap | 1.27.0 | Structured logging |
| google/uuid | 1.6.0 | UUID generation |
| godotenv | 1.5.1 | Env file loading |
| gorm/datatypes | - | JSONB support |

### Architecture

- **Pattern**: Handler → Service → Repository → GORM → PostgreSQL
- **Task System**: In-memory task manager, 5-worker pool, PostgreSQL persistence
- **Migration**: Auto-migration via GORM `AutoMigrate()` on startup
- **Server**: HTTP timeouts 120s read/write, 180s idle, port 8000
- **Shutdown**: Graceful with 30s timeout

### Build & Deployment

- Multi-stage Docker build (Ubuntu 24.04 base)
- Bundled runtime: Node.js 20.16.0, pnpm, Foundry (forge/cast/anvil)
- CGO disabled for portability

---

## 4. trh-platform-ui (Web Frontend)

### Core

| Category | Technology | Version |
|----------|------------|---------|
| Framework | Next.js (App Router) | 15.5.9 |
| UI Framework | React | 19.2.3 |
| Language | TypeScript | 5.x |
| Styling | Tailwind CSS | v4 |
| Component Library | shadcn/ui + Radix UI | - |

### UI & Components

| Library | Version | Purpose |
|---------|---------|---------|
| Radix UI | v1-2 | Primitive UI components |
| shadcn/ui | - | Styled component system (New York) |
| lucide-react | 0.525.0 | Icons |
| class-variance-authority | 0.7.1 | Variant styling |
| clsx | 2.1.1 | Class name utility |
| tailwind-merge | 3.3.1 | Tailwind class dedup |
| tw-animate-css | 1.3.5 | Animations |

### State & Data

| Library | Version | Purpose |
|---------|---------|---------|
| TanStack React Query | 5.90.12 | Server state management |
| react-hook-form | 7.60.0 | Form management |
| @hookform/resolvers | 5.1.1 | Form schema validation |
| zod | 4.0.5 | Schema validation |
| axios | 1.10.0 | HTTP client |

### Web3

| Library | Version | Purpose |
|---------|---------|---------|
| ethers | 6.x | Ethereum interaction |
| bip39 | 3.1.0 | Mnemonic phrases |

### Development & Quality

| Tool | Version | Purpose |
|------|---------|---------|
| ESLint | 9.x | Linting |
| eslint-config-next | - | Next.js rules |
| MSW | 2.12.14 | API mocking |
| next-runtime-env | 3.3.0 | Client-side env vars |
| react-hot-toast | 2.5.2 | Toast notifications |

### Configuration

- **Path aliases**: `@/*` → `./src/*`
- **RSC**: React Server Components enabled
- **API proxy**: `/api/proxy/` through Next.js middleware
- **Auth**: Token management via localStorage
- **Theming**: CSS Variables

---

## Shared Technology Matrix

아래는 4개 저장소에서 공통으로 사용하는 기술 영역을 정리한 것이다.

| Technology | trh-platform | trh-sdk | trh-backend | trh-platform-ui |
|------------|:---:|:---:|:---:|:---:|
| TypeScript | ✅ | - | - | ✅ |
| Go | - | ✅ | ✅ | - |
| React | ✅ | - | - | ✅ |
| ethers.js | ✅ | - | - | ✅ |
| go-ethereum | - | ✅ | ✅ | - |
| AWS SDK | ✅ | ✅ | ✅ | - |
| BIP39/BIP32 | ✅ | ✅ | ✅ | ✅ |
| Docker | ✅ | ✅ | ✅ | - |
| Zod | ✅ | - | - | ✅ |
| PostgreSQL | - | - | ✅ | - |
| Terraform | - | ✅ | - | - |
| Kubernetes | - | ✅ | - | - |

---

## Data Flow

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────┐     ┌─────────────┐
│  trh-platform    │────▶│  trh-platform-ui │────▶│ trh-backend │────▶│   trh-sdk   │
│  (Electron)      │     │  (Next.js Web)   │     │ (Gin API)   │     │  (Go CLI)   │
│                  │     │                  │     │             │     │             │
│  Desktop shell   │     │  Deployment UI   │     │  REST API   │     │  L2 Deploy  │
│  Key management  │     │  Stack config    │     │  Task mgmt  │     │  Infra mgmt │
│  AWS auth        │     │  Monitoring      │     │  Auth/RBAC  │     │  Contracts  │
└─────────────────┘     └──────────────────┘     └──────┬──────┘     └─────────────┘
                                                        │
                                                        ▼
                                                 ┌─────────────┐
                                                 │ PostgreSQL   │
                                                 │ (Port 5432)  │
                                                 └─────────────┘
```

---

*Last updated: 2026-04-07*
