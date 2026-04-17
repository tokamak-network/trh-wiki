---
updated: 2026-04-17
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

---

## Gaming/Full Preset 추가 단계 (DRB 통합)

Gaming/Full preset 선택 시 DRB(Distributed Random Beacon) 자동 통합:

### Genesis 주입
1. `@tokamak-network/commit-reveal2-contracts@1.0.0` 아티팩트 다운로드
2. Cancun EVM에서 생성자 시뮬레이션 → 런타임 bytecode 획득
3. `genesis.json` 패치: `0xc0D3…0060`(impl) + `0x4200…0060`(proxy ERC1967 slot) 주입
4. Regular 3개 주소(BIP44 index 5/6/7)에 native 토큰 잔액 alloc 주입 (`max(activationThreshold × 10, 1e18)`)

### 키 및 Peer ID 파생
- Regular 개인 키: BIP44 `m/44'/60'/0'/0/{5,6,7}` (결정적)
- Leader + Regular peer ID: libp2p Ed25519, `sha256(mnemonic + "|drb-peer-id-v1|" + role)` 시드 기반 (결정적)

### 컨테이너 기동 (2-phase boot)
1. `drb-postgres`, `drb-postgres-regular-{1,2,3}` healthy
2. `BootstrapDRBPeerIDFiles()` — peer ID 파일을 static-key 볼륨에 주입
3. `drb-leader`, `drb-regular-{1,2,3}` 기동
4. 모두 healthy 대기

### 온체인 활성화
- 각 Regular 키로 `CommitReveal2L2.depositAndActivate()` 순차 호출
- `getActivatedOperators()` 결과에 3개 주소 존재 확인

### 검증
- `cast code 0x4200…0060` — predeploy 존재
- `cast call 0x4200…0060 "getActivatedOperators()(address[])"` — 3 Regular 주소
- `docker inspect drb-leader drb-regular-1 drb-regular-2 drb-regular-3` — healthy
- `trh-sdk/scripts/drb_smoke.sh` — 5초 이내 전체 검증

### 구현 경로
- `trh-sdk/pkg/stacks/thanos/drb_genesis.go` — genesis 주입
- `trh-sdk/pkg/stacks/thanos/drb_orchestrator.go` — DRBAccounts 파생, peer ID 부트스트랩
- `trh-sdk/pkg/stacks/thanos/drb_activate.go` — on-chain 활성화
- `trh-sdk/pkg/stacks/thanos/templates/local-compose.yml.tmpl` — 컨테이너 템플릿
