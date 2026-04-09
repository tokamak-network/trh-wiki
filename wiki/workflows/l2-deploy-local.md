---
updated: 2026-04-09
sources:
  - raw/architecture/local-l2-deployment-test-guide.md
related:
  - "[[presets]]"
  - "[[l2-deployment]]"
  - "[[trh-platform-ui]]"
  - "[[trh-backend]]"
  - "[[trh-sdk]]"
  - "[[port-conflicts]]"
  - "[[docker-health-checks]]"
tags: [workflow]
---

# Local Docker L2 Deployment

trh-platform Desktop App에서 L1 Sepolia 기반 로컬 Docker L2를 배포하는 워크플로우.

**배포 모델**: L1 컨트랙트는 실제 Sepolia 테스트넷에 배포, L2 노드(op-geth, op-node, op-batcher, op-proposer)는 로컬 Docker Compose로 실행.

---

## 사전 요구사항

| 항목 | 요구사항 |
|------|---------|
| OS | macOS 13+ 또는 Ubuntu 22.04+ |
| Docker | Docker Desktop 4.x+ 실행 중 |
| Sepolia RPC URL | Alchemy 등 유효한 URL |
| Sepolia Beacon URL | publicnode 또는 동등한 URL |
| Seed Phrase | 12단어 BIP39 니모닉 (Sepolia ETH 보유) |
| Sepolia ETH | Admin: 0.5+, Batcher: 0.3+, Proposer: 0.3+ ETH |
| 디스크 여유 | 20GB 이상 |
| 포트 가용 | 8545, 8546, 8548, 8551, 8560, 9545 미사용 |

---

## 배포 단계

### 1. 프리셋 위자드 진입
- Sidebar → Rollup → Create New Rollup → Preset Wizard 탭

### 2. Basic Info 설정
- Infrastructure Provider: **Local Docker** 선택
  - AWS Configuration 섹션 자동 숨김
  - Network 자동 Testnet(Sepolia)로 전환 (Mainnet 비활성화)
- L1 RPC URL 입력 (필수)
- Seed Phrase 입력

### 3. Config Review
- 파라미터 확인 (Expert Mode로 수정 가능)
- Funding Status 확인 — 3개 계정 잔액이 충분해야 배포 버튼 활성화

### 4. 배포 실행
API 요청: `POST /api/v1/stacks/thanos/preset-deploy`
```json
{
  "infraProvider": "local",
  "l1RpcUrl": "...",
  "l1BeaconUrl": "...",
  "seedPhrase": "...",
  "preset": "General"
}
```

### 5. 배포 진행 순서
1. `deploy-l1-contracts` — Sepolia에 L1 컨트랙트 배포
2. `deploy-aws-infra` (로컬 분기) — Docker Compose로 L2 노드 시작
3. op-geth, op-node, op-batcher, op-proposer 컨테이너 순차 기동

---

## 배포 완료 검증

```bash
# 컨테이너 상태 확인
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# L2 RPC 응답 확인
curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

# 30초 후 블록 생성 확인
curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

기대 컨테이너: `op-geth`(8545/8546/8551), `op-node`(9545/7300), `op-batcher`(8548), `op-proposer`(8560)

---

## 정리 (Teardown)

Dashboard → Stack → Delete → `docker compose down -v`
→ 모든 L2 컨테이너 + 볼륨(op-geth-data, blockscout-db-data) 제거

---

## 알려진 이슈

- **동시 배포 불가**: L2 배포는 반드시 순차 실행 → [[sequential-l2-deploy]]
- **포트 충돌**: 8545 등 포트가 점유된 경우 Docker Compose 실패 → [[port-conflicts]]
- **가스 리밋**: L1 컨트랙트 배포 실패 시 → [[l1-gas-limits]]
