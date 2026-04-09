---
updated: 2026-04-09
sources:
  - raw/architecture/presets-implementation.md
  - raw/architecture/preset-deployment-flow.html
related:
  - "[[architecture]]"
  - "[[l2-deployment]]"
  - "[[cross-trade]]"
  - "[[trh-sdk]]"
  - "[[trh-platform-ui]]"
tags: [concept]
---

# Presets

4가지 preset이 L2 롤업의 genesis config, predeploy 컨트랙트, 모듈(Helm chart) 구성을 결정한다.

---

## Preset 정의

| Preset | 포함 내용 | 배포 시간 (Testnet) |
|--------|---------|------------------|
| **General** | OP Stack 표준 + TON (L2 Native) + WTON + L2 ETH | ~12분 |
| **DeFi** | General + Uniswap V3 + USDC Bridge + CrossTrade | ~18분 |
| **Gaming** | General + DRB VRF + ERC-4337 EntryPoint/Paymaster | ~20분 |
| **Full** | DeFi + Gaming 전부 | ~25분 |

---

## 목표 사용자 입력 수

| 항목 | 현재 | 목표 |
|------|------|------|
| 배포 시 입력 | 26개 | 5개 (AWS Key 2 + Preset + Chain Name + Network) |
| 모듈 배포 입력 | 28개+ | 0개 |

Preset 선택 하나로 나머지 파라미터가 자동 결정된다.

---

## 각 Preset의 활성 모듈

| 모듈 | General | DeFi | Gaming | Full |
|------|:-------:|:----:|:------:|:----:|
| Explorer (Blockscout) | ✅ | ✅ | ✅ | ✅ |
| Bridge | ✅ | ✅ | ✅ | ✅ |
| Monitoring (Grafana) | - | ✅ | ✅ | ✅ |
| CrossTrade | - | ✅ | - | ✅ |
| Staking V2 | - | ✅ | ✅ | ✅ |
| DRB VRF | - | - | ✅ | ✅ |
| AA Paymaster | - | - | ✅ | ✅ |
| Backup & Recovery | - | - | - | ✅ |

---

## 서비스 포트 (로컬 배포 시)

| 서비스 | URL |
|--------|-----|
| L2 RPC | localhost:8545 |
| L2 WebSocket | localhost:8546 |
| Bridge | localhost:3001 |
| Explorer (Blockscout) | localhost:4001 |
| Monitoring (Grafana) | localhost:3002 |

---

## CrossTrade 통합 (DeFi / Full)

DeFi/Full Preset에서는 CrossTrade가 자동 배포된다.
배포 방식: L1 Deposit Transaction (Genesis Predeploy 아님)
→ [[cross-trade]], [[deposit-tx]], [[deposit-tx-vs-genesis-predeploy]]

---

## Gaming Preset 특이사항

- DRB VRF: 검증 가능한 랜덤 수 생성 (온체인 게임용)
- ERC-4337: Account Abstraction EntryPoint + Paymaster
- CrossTrade **미포함** — Gaming은 DeFi 모듈 없음
