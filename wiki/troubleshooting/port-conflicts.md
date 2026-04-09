---
updated: 2026-04-09
sources:
  - raw/architecture/local-l2-deployment-test-guide.md
related:
  - "[[l2-deploy-local]]"
  - "[[sequential-l2-deploy]]"
  - "[[docker-compose-lifecycle]]"
tags: [troubleshooting]
---

# Port Conflicts

로컬 L2 배포 시 포트 충돌로 Docker Compose 실행이 실패하는 경우.

---

## 사용 포트 목록

| 포트 | 컨테이너 | 프로토콜 |
|------|---------|---------|
| 8545 | op-geth | HTTP RPC |
| 8546 | op-geth | WebSocket |
| 8551 | op-geth | Auth RPC |
| 8548 | op-batcher | HTTP |
| 8560 | op-proposer | HTTP |
| 9545 | op-node | P2P |
| 7300 | op-node | Metrics |
| 3001 | bridge | HTTP |
| 4001 | blockscout | HTTP |
| 3002 | grafana | HTTP |

---

## 진단

```bash
# 포트 점유 프로세스 확인 (macOS/Linux)
lsof -i :8545
lsof -i :8546,8548,8551,8560,9545

# 또는
ss -tlnp | grep -E '8545|8546|8548|8551|8560|9545'
```

---

## 해결

```bash
# 점유 프로세스 종료
kill -9 $(lsof -ti :8545)

# 이전 L2 컨테이너가 남아있는 경우
docker ps --filter "name=op-"
docker compose -f <compose-file> down -v
```

---

## 예방

- 동시 L2 배포 금지 → [[sequential-l2-deploy]]
- 배포 전 trh-platform이 자동으로 포트 가용성 체크 (PortConflict 모달)
- 배포 완료 후 반드시 teardown(stack delete) 실행
