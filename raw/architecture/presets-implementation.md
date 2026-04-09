# Tokamak Rollup Hub — Preset + MCP AI 배포 시스템 구현 계획

> **Self-Hosted 소유권 100% 유지 + Preset 기반 유스케이스 차별화 + EOA 펀딩 자동화 + 모듈 입력 제로화**
>
> 2026.03.10 | Tokamak Network

## 핵심 수치

| 항목 | 현재 | 목표 |
|------|------|------|
| 배포 시 사용자 입력 | 26개 | 5개 (AWS Key 2 + Preset + Chain Name + Network) |
| 모듈 배포 시 입력 | 28개+ | 0개 |
| Testnet 총 소요 | 2~3시간+ | ~25분 |
| Mainnet 총 소요 | 3시간+ | ~40분 |
| Private Key 관리 | 4개 수동 생성 | Seed 1개 → 4개 자동 파생 |
| EOA 펀딩 (Testnet) | 수동 faucet | 자동 Faucet (0분) |

## 문서 구조

```
trh-implementation-plan/
├── README.md                          ← 이 파일 (전체 개요)
├── 01-overview.md                     ← 배경, 전략, Preset 정의, 소유권 보장
├── 02-eoa-funding.md                  ← EOA 펀딩 해결 설계 (A+B+C)
├── repos/
│   ├── tokamak-thanos.md              ← Genesis predeploy 변경
│   ├── trh-sdk.md                     ← Preset, 키 파생, 펀딩, 모듈 자동화
│   ├── trh-backend.md                 ← API 엔드포인트
│   ├── trh-platform-ui.md             ← UI 컴포넌트
│   ├── trh-mcp-server.md              ← MCP Tool + npm 배포
│   └── tokamak-thanos-stack.md        ← Helm charts
├── 03-user-journey.md                 ← 최종 Testnet/Mainnet 여정
├── 04-e2e-tests.md                    ← E2E 테스트 시나리오
├── 05-scenarios.md                    ← 실 예제 시나리오
└── 06-roadmap.md                      ← 구현 로드맵 (14주)
```

## 대상 레포지토리

| 레포 | 역할 | 주요 변경 |
|------|------|-----------|
| [tokamak-thanos](repos/tokamak-thanos.md) | L2 Core (OP Stack Fork) | Preset별 genesis predeploy 추가 |
| [trh-sdk](repos/trh-sdk.md) | Deployment CLI (Go) | `--preset`, Seed HD 파생, 펀딩 도우미, 모듈 자동화 |
| [trh-backend](repos/trh-backend.md) | Platform API (Go) | Preset API, Funding Status API, 모듈 설정 API |
| [trh-platform-ui](repos/trh-platform-ui.md) | Web Dashboard (Next.js) | Preset 카드, FundingStatus, 3단계 위자드 |
| [trh-mcp-server](repos/trh-mcp-server.md) | AI 배포 (MCP/TypeScript) | 7개 Tool, npm 패키지 배포 |
| [tokamak-thanos-stack](repos/tokamak-thanos-stack.md) | Infra (Helm/Terraform) | Preset별 values, 새 모듈 chart |

## Preset 정의

| Preset | Genesis Predeploy | 모듈 (Helm) | 배포 시간 |
|--------|-------------------|-------------|-----------|
| **General 🌐** | OP Standard + L2 Native Token (TON) + WTON + L2 ETH | Explorer, Bridge | Testnet ~12분 / Mainnet ~15분 |
| **DeFi 💰** | General + Uniswap V3 + USDC Bridge | Explorer, Bridge, Monitoring, CrossTrade, Staking V2 | Testnet ~18분 / Mainnet ~22분 |
| **Gaming 🎮** | General + DRB VRF + ERC-4337 EntryPoint/Paymaster | Explorer, Bridge, Monitoring, DRB, Staking V2 | Testnet ~20분 / Mainnet ~25분 |
| **Full 🏢** | DeFi + Gaming genesis 전부 | 모든 모듈 + Backup & Recovery | Testnet ~25분 / Mainnet ~30분 |

## 구현 로드맵 (요약)

| Phase | 기간 | 핵심 | 레포 |
|-------|------|------|------|
| **Phase 0** | 2주 | SDK `--preset` + 펀딩 도우미 + 모듈 자동화 | trh-sdk, trh-backend |
| **Phase 1** | 4주 | DRB VRF predeploy + Gaming Preset + Faucet | tokamak-thanos, tokamak-thanos-stack |
| **Phase 2** | 4주 | ERC-4337 predeploy + Full Preset + 모듈 설정 UI | tokamak-thanos, trh-backend, trh-platform-ui |
| **Phase 3** | 2주 | MCP 7개 Tool + npm 배포 | trh-mcp-server |
| **Phase 4** | 2주 | Preset 카드 UI + FundingStatus + 전체 E2E | trh-platform-ui |
