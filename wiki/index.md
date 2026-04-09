---
updated: 2026-04-09
---

# TRH Wiki Index

Master index of all wiki pages. Updated on every ingest operation.

---

## Overview

| Page | Summary |
|------|---------|
| [[architecture]] | Full system architecture map — 4 repos, their roles, and how they connect |

## Components

### TRH 플랫폼

| Page | Summary |
|------|---------|
| [[trh-platform]] | Electron desktop app — main/renderer/preload architecture, IPC patterns |
| [[trh-sdk]] | Go CLI deployment engine — preset configs, L2 deployment orchestration |
| [[trh-backend]] | Go REST API — Gin + GORM, endpoints, Docker lifecycle management |
| [[trh-platform-ui]] | Next.js web frontend — embedded in Electron WebContentsView |
| [[cross-trade]] | CrossTrade DeFi integration — L1→L2 deposit tx pattern, dApp service |

### Thanos 인프라

| Page | Summary |
|------|---------|
| [[tokamak-thanos]] | OP Stack v1.7.7 포크 — op-node, op-batcher, op-proposer, 컨트랙트, TypeScript SDK |
| [[tokamak-thanos-stack]] | Terraform + Helm IaC — AWS EKS 인프라, 체인 노드 K8s 배포 |
| [[tokamak-thanos-geth]] | go-ethereum OP Stack 포크 — L2 실행 계층, Deposit TX, Engine API |

## Concepts

| Page | Summary |
|------|---------|
| [[presets]] | General / DeFi / Gaming / Full — what each preset includes and why |
| [[deposit-tx]] | L1→L2 Deposit Transaction pattern via OptimismPortal |
| [[l2-deployment]] | End-to-end L2 deployment flow — from preset selection to running chain |
| [[keystore]] | Electron safeStorage + BIP44 key derivation — mnemonic → deployer keys |
| [[aws-sso]] | AWS SSO credential flow — profile listing, OIDC login, role assumption |
| [[docker-compose-lifecycle]] | How the platform manages Docker Compose services at runtime |

## Workflows

| Page | Summary |
|------|---------|
| [[local-dev]] | Local development environment setup |
| [[l2-deploy-local]] | Full walkthrough: deploying an L2 chain locally via Docker Compose |
| [[ec2-deploy]] | AWS EC2 deployment via Terraform — one-time setup and update flow |
| [[release]] | Release process — building macOS/Windows/Linux binaries, versioning |

## Decisions

| Page | Summary |
|------|---------|
| [[deposit-tx-vs-genesis-predeploy]] | Why L1 Deposit Tx was chosen over Genesis Predeploy for CrossTrade |
| [[abigen-vs-manual-calldata]] | abigen bindings vs manual keccak256 calldata construction |
| [[separate-compose-for-crosstrade]] | Why CrossTrade dApp uses a separate docker-compose file |
| [[sequential-l2-deploy]] | Why L2 deployments must run sequentially (port conflict analysis) |

## Troubleshooting

| Page | Summary |
|------|---------|
| [[port-conflicts]] | Port conflict detection, resolution, and prevention |
| [[l1-gas-limits]] | L1 gas limit tuning for OptimismPortal deposit transactions |
| [[docker-health-checks]] | Backend health check timeouts and retry strategies |
| [[l2-deposit-verification]] | Verifying L2 deposit transaction execution — polling strategy |

---

*Pages listed here but not yet created are stubs — run `lint` to see the full list.*
