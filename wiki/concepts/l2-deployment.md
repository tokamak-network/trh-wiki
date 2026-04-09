---
updated: 2026-04-09
sources:
  - raw/architecture/local-l2-deployment-test-guide.md
  - raw/architecture/trh-deployment-flow.html
  - raw/architecture/preset-deployment-flow.html
related:
  - "[[presets]]"
  - "[[trh-sdk]]"
  - "[[trh-backend]]"
  - "[[l2-deploy-local]]"
  - "[[ec2-deploy]]"
  - "[[deposit-tx]]"
tags: [concept]
---

# L2 Deployment

L2 롤업 배포의 전체 흐름. Preset 선택부터 체인 가동까지.

---

## 배포 단계 요약

```
1. Preset 선택         사용자가 General / DeFi / Gaming / Full 선택
2. 파라미터 입력       Chain Name, Network, L1 RPC, Seed Phrase
3. L1 컨트랙트 배포    Sepolia (또는 Mainnet)에 OptimismPortal 등 배포
4. L2 인프라 기동      Local: Docker Compose / AWS: EC2 + Helm
5. Preset 모듈 배포    CrossTrade, DRB, AA Paymaster 등 (Preset별 조건부)
6. 검증                eth_chainId, eth_blockNumber, 모듈 헬스 체크
```

---

## 배포 타겟별 차이

| 항목 | Local Docker | AWS EC2 |
|------|-------------|---------|
| 인프라 | Docker Compose | Terraform + EC2 |
| 네트워크 | Testnet 전용 | Testnet + Mainnet |
| AWS 자격증명 | 불필요 | 필수 |
| L2 노드 위치 | localhost | EC2 인스턴스 |
| 비용 | 무료 | EC2 + 네트워크 비용 |

---

## L2 노드 구성 요소

| 컨테이너 | 포트 | 역할 |
|---------|------|------|
| op-geth | 8545 (RPC), 8546 (WS), 8551 (Auth) | L2 실행 레이어 |
| op-node | 9545, 7300 | 롤업 노드 (L1 동기화) |
| op-batcher | 8548 | L2 배치 → L1 제출 |
| op-proposer | 8560 | 상태 루트 → L1 제출 |

---

## 키 관리

Seed Phrase 1개 → BIP44 파생으로 4개 키 자동 생성:
- Admin key — L1 컨트랙트 owner
- Batcher key — op-batcher 서명
- Proposer key — op-proposer 서명
- Deployer key — L2 컨트랙트 배포 (CrossTrade 등)

→ [[keystore]]

---

## DeFi/Full Preset 추가 단계

CrossTrade 자동 배포 (L1 Deposit Tx 방식):
1. OptimismPortal.depositTransaction() 호출 → L2 컨트랙트 생성
2. L1 setChainInfo 등록
3. CrossTrade dApp 컨테이너 추가 (별도 docker-compose 파일)

→ [[cross-trade]], [[deposit-tx]]
