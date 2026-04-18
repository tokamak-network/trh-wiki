---
updated: 2026-04-18
---

# TRH Wiki Index

Master index of all wiki pages. Updated on every ingest operation.

---

## Overview

| Page | Summary |
|------|---------|
| [[architecture]] | Full system architecture map — 4 repos, their roles, and how they connect |

## Components

### Core

| Page | Summary |
|------|---------|
| [[trh-platform]] | Electron desktop app — main/renderer/preload architecture, IPC patterns |
| [[trh-sdk]] | Go CLI deployment engine — preset configs, L2 deployment orchestration |
| [[trh-backend]] | Go REST API — Gin + GORM, endpoints, Docker lifecycle management |
| [[trh-platform-ui]] | Next.js web frontend — embedded in Electron WebContentsView |
| [[tokamak-thanos]] | OP Stack v1.7.7 포크 — op-node, op-batcher, op-proposer, 컨트랙트, TypeScript SDK |
| [[tokamak-thanos-stack]] | Terraform + Helm IaC — AWS EKS 인프라, 체인 노드 K8s 배포 |
| [[tokamak-thanos-geth]] | go-ethereum OP Stack 포크 — L2 실행 계층, Deposit TX, Engine API |
| [[tokamak-rollup-hub-v2]] | Rollup Hub 마케팅 웹사이트 — 제품 허브, TRH Desktop 릴리즈 연동 |

### Integration

| Page | Summary |
|------|---------|
| [[cross-trade]] | CrossTrade DeFi integration — L1→L2 deposit tx pattern, dApp service |
| [[thanos-bridge]] | L1↔L2 자산 브리지 DApp — Next.js, Thanos SDK, Wagmi |
| [[drb-project]] | DRB 프로젝트 umbrella — 프로토콜 흐름, 상태 머신, operator lifecycle, dispute/slashing, L2 gas |
| [[commit-reveal2]] | 분산 랜덤 비컨(DRB) 스마트 컨트랙트 — 2단계 Commit-Reveal, last revealer attack 방지 (part of [[drb-project]]) |
| [[drb-node]] | DRB Go 노드 구현체 — Leader/Regular 아키텍처, LibP2P, PostgreSQL (part of [[drb-project]]) |

## Concepts

| Page | Summary |
|------|---------|
| [[presets]] | General / DeFi / Gaming / Full — what each preset includes and why |
| [[deposit-tx]] | L1→L2 Deposit Transaction pattern via OptimismPortal |
| [[l2-deployment]] | End-to-end L2 deployment flow — from preset selection to running chain |
| [[keystore]] | Electron safeStorage + BIP44 key derivation — mnemonic → deployer keys |
| [[docker-compose-lifecycle]] | How the platform manages Docker Compose services at runtime |

## Workflows

| Page | Summary |
|------|---------|
| [[local-dev]] | 레포별 개발 서버 기동, 환경 변수, mock 패턴 |
| [[l2-deploy-local]] | Full walkthrough: deploying an L2 chain locally via Docker Compose |
| [[ec2-deploy]] | AWS EC2 deployment via Terraform — one-time setup and update flow |
| [[release]] | Electron DMG/NSIS/AppImage 빌드, Docker 이미지 배포, 버전 고정 패턴 |
| [[testing]] | 테스트 스택, 실행 명령어, E2E 3가지 모드, Vitest/Playwright 패턴 |

## Deployment Analysis

| Page | Summary |
|------|---------|
| [[thanos-deployer-analysis]] | Complete deployment logic analysis — 8-layer architecture, 6-phase flow, 51 functions, critical pitfalls |

## Decisions

| Page | Summary |
|------|---------|
| [[deposit-tx-vs-genesis-predeploy]] | Why L1 Deposit Tx was chosen over Genesis Predeploy for CrossTrade |
| [[abigen-vs-manual-calldata]] | abigen bindings vs manual keccak256 calldata construction |
| [[separate-compose-for-crosstrade]] | Why CrossTrade dApp uses a separate docker-compose file |
| [[sequential-l2-deploy]] | Why L2 deployments must run sequentially (port conflict analysis) |
| [[tech-debt-and-risks]] | Known bugs, tech debt, security concerns, dependency risks |
| [[requirements-v1]] | CrossTrade 통합 v1 요구사항 30개 — 전체 완료, Phase traceability 포함 |
| [[deploy-methods-comparison]] | Deploy.s.sol (Foundry) vs tokamak-deployer (Go) — L1 배포 방식 비교, 하이브리드 전환 상태 |

## Troubleshooting

| Page | Summary |
|------|---------|
| [[port-conflicts]] | Port conflict detection, resolution, and prevention |
| [[l1-gas-limits]] | L1 gas limit tuning for OptimismPortal deposit transactions |
| [[docker-health-checks]] | Backend health check timeouts and retry strategies |
| [[l2-deposit-verification]] | Verifying L2 deposit transaction execution — polling strategy |
| [[l1-deposit-tx-pitfalls]] | L1 Deposit Tx CrossTrade 배포 시 13개 주요 함정과 방지법 |
| [[tokamak-deployer-logging]] | Debugging contract deployment hangs via comprehensive logging (v1.0.1+) |
| [[tokamak-deployer-gas-price]] | Fixed gas price reuse strategy (v0.0.5+) — 5m47s measured on Sepolia, 0 retries |
| [[drb-local-compose-path-template-bugs]] | DRB gaming preset 로컬 배포 시 드러난 5개 경로·템플릿 버그 (path, FuncMap, range-scope, PORT, op-geth volume) |
| [[forge-l2genesis-silent-slow]] | forge L2Genesis 단계 로그 무음·과도 지연 — Infow 오용, CombinedOutput, 불필요 --rpc-url |

---

*Pages listed here but not yet created are stubs — run `lint` to see the full list.*
