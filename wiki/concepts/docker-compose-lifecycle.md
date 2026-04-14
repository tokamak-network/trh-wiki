---
updated: 2026-04-15
sources:
  - raw/architecture/tech-stack.md
  - raw/decisions/PRD-CrossTrade-TRH-Integration-v2.1.md
related:
  - "[[trh-platform]]"
  - "[[trh-backend]]"
  - "[[trh-sdk]]"
  - "[[separate-compose-for-crosstrade]]"
  - "[[port-conflicts]]"
  - "[[l2-deploy-local]]"
tags: [concept]
---

# Docker Compose Lifecycle

trh-platform이 로컬 L2 스택을 Docker Compose로 관리하는 방식. 실제 컨테이너 오케스트레이션은 trh-backend → trh-sdk 경로를 통해 이루어지며, trh-platform의 `docker.ts`는 Desktop 앱 레벨의 인터페이스를 담당한다.

---

## 레이어 구조

```
trh-platform (Electron)
  └─ docker.ts          — Docker Compose up/down/pull, 헬스 체크 IPC

trh-backend (Gin)
  └─ Docker socket       — 컨테이너 라이프사이클 API 제공

trh-sdk (Go)
  └─ DeployLocalInfrastructure — docker compose 명령어 조합 및 실행
```

---

## Compose 파일 구성

로컬 배포 시 Preset에 따라 사용하는 Compose 파일이 달라진다.

| Preset | 실행 명령어 |
|--------|-----------|
| General / Gaming | `docker compose -f docker-compose.yml up -d` |
| DeFi / Full | `docker compose -f docker-compose.yml -f docker-compose.crosstrade.yml up -d` |

`docker-compose.crosstrade.yml`을 별도 파일로 분리한 이유 → [[separate-compose-for-crosstrade]]

---

## 로컬 스택 컨테이너 목록

| 컨테이너 | 포트 | 역할 |
|---------|------|------|
| op-geth | 8545 (HTTP RPC), 8546 (WS), 8551 (Auth RPC) | L2 실행 계층 |
| op-node | 9545 (P2P), 7300 (Metrics) | L2 합의 계층 |
| op-batcher | 8548 | Batch submission |
| op-proposer | 8560 | Output root 제출 |
| crosstrade-dapp | 3001 | CrossTrade UI (DeFi/Full만) |
| thanos-bridge | 3001 | Bridge DApp (preset 따라 다름) |
| blockscout | 4001 | 블록 익스플로러 |
| grafana | 3002 | 모니터링 |

포트 충돌 진단 → [[port-conflicts]]

---

## 핵심 파일

- `trh-platform/src/main/docker.ts` — Electron에서 docker compose 명령 실행, 헬스 체크
- `trh-backend/pkg/services/thanos/deployment.go` — `DeployLocalInfrastructure` 호출
- `trh-sdk/pkg/stacks/thanos/deploy_chain.go` — `deployNetworkToLocal`, compose file 선택 로직

---

## 헬스 체크

trh-platform은 컨테이너 기동 후 L2 RPC(`eth_chainId`)가 응답할 때까지 폴링한다. 타임아웃/재시도 전략 → [[docker-health-checks]]

---

## 주의사항

- 동시 L2 배포 불가 — 포트 충돌 발생 → [[sequential-l2-deploy]]
- 배포 후 반드시 teardown(`docker compose down -v`) 실행
- trh-platform이 기동 시 자동으로 포트 가용성 체크 (PortConflict 모달 표시)
