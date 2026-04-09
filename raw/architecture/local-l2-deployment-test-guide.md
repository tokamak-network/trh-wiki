# Local L2 Rollup Testnet Deployment — QA Checklist

> **목적**: trh-platform Desktop App에서 L1 Sepolia 기반 로컬 Docker L2 배포 기능이 정상 동작하는지 검증하는 체크리스트입니다.
>
> **배포 모델**: L1 컨트랙트는 실제 Sepolia 테스트넷에 배포되며, L2 노드(op-geth, op-node, op-batcher, op-proposer/op-challenger)는 로컬 Docker Compose로 실행됩니다.

---

## 사전 준비 (Prerequisites)

| 항목 | 요구사항 |
|------|---------|
| OS | macOS 13+ 또는 Ubuntu 22.04+ |
| Docker | Docker Desktop 4.x+ 실행 중 (`docker ps` 정상 응답) |
| Desktop App | trh-platform Electron App 최신 버전 설치 및 실행 |
| Sepolia RPC URL | `https://eth-sepolia.g.alchemy.com/v2/...` 형식의 유효한 URL |
| Sepolia Beacon URL | `https://ethereum-sepolia-beacon-api.publicnode.com` 또는 동등한 URL |
| Seed Phrase | 12단어 BIP39 니모닉 (Sepolia ETH 보유 계정) |
| Sepolia ETH | Admin: 0.5+ ETH, Batcher: 0.3+ ETH, Proposer: 0.3+ ETH |
| 디스크 여유 공간 | 20GB 이상 |
| 포트 가용성 | 8545, 8546, 8548, 8551, 8560, 9545 미사용 상태 |

---

## Phase 0: Desktop App 실행 및 로그인

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P0-1 | Desktop App 실행 | Electron App 실행 | 로그인 화면 표시, Docker 컨테이너(backend, frontend, postgres) 자동 시작 | |
| P0-2 | 로그인 | 기본 계정(admin@gmail.com / admin)으로 로그인 | 대시보드로 이동 | |
| P0-3 | Docker socket 접근 | `docker ps`로 backend 컨테이너 확인 | backend 컨테이너가 `/var/run/docker.sock` 마운트됨 확인: `docker inspect trh-backend \| grep docker.sock` | |

---

## Phase 1: 로컬 배포 위자드 진입

### 1-1. 프리셋 위자드 시작

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P1-1 | 롤업 생성 버튼 | 사이드바 → Rollup → Create New Rollup | `/rollup/create` 페이지 이동, 위자드 모드 선택 화면 표시 | |
| P1-2 | 프리셋 모드 선택 | "Preset Wizard" 탭 선택 | 프리셋 선택 카드(General, Enterprise 등) 표시 | |
| P1-3 | 프리셋 선택 | General 프리셋 선택 | 프리셋 카드 하이라이트, Next 버튼 활성화 | |

---

## Phase 2: Basic Info Step — Infrastructure Provider 선택 (핵심)

### 2-1. UI 렌더링

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P2-1 | 인프라 선택 카드 표시 | Step 2 진입 | "Infrastructure Provider" 섹션에 AWS Cloud / Local Docker 두 버튼 표시 | |
| P2-2 | 기본값 AWS | Step 2 진입 직후 | AWS Cloud 버튼이 파란색 테두리로 선택된 상태 | |
| P2-3 | AWS 선택 시 전체 UI | AWS 버튼 클릭 유지 | AWS Configuration 섹션(Access Key, Secret Key, Region) 표시됨 | |
| P2-4 | AWS 선택 시 Mainnet 활성 | AWS 선택 상태 → Network 드롭다운 | "Mainnet (Ethereum)" 옵션 선택 가능 (비활성화되지 않음) | |

### 2-2. Local Docker 선택

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P2-5 | Local Docker 버튼 클릭 | Local Docker 버튼 클릭 | 버튼이 파란색 테두리로 전환, AWS 버튼 비선택 상태 | |
| P2-6 | AWS 섹션 숨김 | Local 선택 후 | "AWS Configuration" 카드(Access Key, Secret Key, Region) 화면에서 사라짐 | |
| P2-7 | Mainnet 옵션 비활성화 | Local 선택 후 Network 드롭다운 | "Mainnet (Ethereum) — not available for local" 표시, 선택 불가 | |
| P2-8 | Mainnet → Testnet 자동 전환 | Mainnet 선택 상태에서 Local 버튼 클릭 | Network 값이 자동으로 "Testnet (Sepolia)"로 변경됨 | |
| P2-9 | L1 RPC/Beacon URL 표시 | Local 선택 상태 | L1 Connection 섹션(L1 RPC URL, L1 Beacon URL)은 그대로 표시됨 | |
| P2-10 | Seed Phrase 표시 | Local 선택 상태 | Account Setup(Seed Phrase 입력) 섹션은 그대로 표시됨 | |

### 2-3. 폼 유효성 검사

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P2-11 | Local 선택 시 AWS 미입력 허용 | Local 선택 후 AWS 필드 비워두고 Next | AWS 관련 에러 메시지 없이 다음 단계 진행 | |
| P2-12 | Local + Mainnet 방지 | Network를 Mainnet으로 강제 설정 시도 | "Local deployment is not supported for Mainnet" 에러 표시 | |
| P2-13 | L1 RPC URL 필수 검증 | Local 선택 후 l1RpcUrl 비워두고 Next | "L1 RPC URL is required" 에러 표시 | |
| P2-14 | 유효하지 않은 URL 검증 | l1RpcUrl에 "not-a-url" 입력 후 Next | "Must be a valid URL" 에러 표시 | |
| P2-15 | Chain Name 형식 검증 | "My Chain!" (대문자, 특수문자) 입력 | "Must be 3-32 lowercase alphanumeric..." 에러 표시 | |

---

## Phase 3: Config Review Step

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P3-1 | 로컬 배포 안내 카드 | Local 선택 후 Step 3 진입 | 파란색 "Local Docker Deployment" 카드 표시 | |
| P3-2 | 서비스 URL 표시 | 로컬 안내 카드 내용 확인 | L2 RPC: localhost:8545, Bridge: localhost:3001, Explorer: localhost:4001, Monitoring: localhost:3002 표시 | |
| P3-3 | 로컬 안내 카드 미표시(AWS) | AWS 선택 후 Step 3 진입 | "Local Docker Deployment" 카드 표시되지 않음 | |
| P3-4 | 프리셋 파라미터 표시 | Step 3 내용 | chainDefaults(block time, batch frequency 등) 표시 | |
| P3-5 | Expert Mode 파라미터 수정 | Expert Mode 토글 ON → 값 변경 | 변경된 필드에 "Modified" 배지 표시 | |

---

## Phase 4: 펀딩 상태 확인 (Funding Status)

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P4-1 | 펀딩 상태 UI 표시 | Step 3 하단 FundingStatus 컴포넌트 | Sepolia 기반 계정(Admin, Batcher, Proposer)의 ETH 잔액 표시 | |
| P4-2 | 부족한 잔액 경고 | 잔액 부족 계정 존재 시 | 해당 계정에 경고 표시, 배포 버튼 비활성화 또는 경고 메시지 | |
| P4-3 | 충분한 잔액 확인 | 잔액 충분 시 | 체크 표시, 배포 버튼 활성화 | |

---

## Phase 5: 배포 실행

### 5-1. API 요청 검증

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P5-1 | Deploy 버튼 클릭 | 모든 필드 입력 후 Deploy 클릭 | `POST /api/v1/stacks/thanos/preset-deploy` 요청 전송 | |
| P5-2 | infraProvider 전송 | 브라우저 DevTools Network 탭 확인 | 요청 body에 `"infraProvider": "local"` 포함 | |
| P5-3 | AWS 필드 미전송 | 요청 body 확인 | `awsAccessKey`, `awsSecretKey`, `awsRegion` 빈 값 또는 미포함 | |
| P5-4 | L1 URL 전송 | 요청 body 확인 | `l1RpcUrl`, `l1BeaconUrl` 입력값이 정상 전송됨 | |

### 5-2. 배포 진행 모니터링

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P5-5 | 배포 시작 상태 | Deploy 클릭 후 | 배포 상태가 "Deploying"으로 전환, 스피너/프로그레스 표시 | |
| P5-6 | Step 1: L1 컨트랙트 배포 | 배포 로그 확인 | "deploy-l1-contracts" 단계 실행 중 로그 스트리밍 | |
| P5-7 | L1 완료 후 Step 2 | 로그 및 진행상태 확인 | "deploy-l1-contracts" 완료 → "deploy-aws-infra" (로컬 분기) 시작 | |
| P5-8 | Docker Compose 실행 로그 | 로그 확인 | op-geth, op-node, op-batcher, op-proposer 컨테이너 시작 로그 확인 | |
| P5-9 | 배포 완료 | 최종 상태 확인 | 스택 상태 "Deployed"로 전환, 대시보드에 체인 정보 표시 | |

---

## Phase 6: L2 노드 동작 검증

### 6-1. Docker 컨테이너 확인

배포 완료 후 호스트 터미널에서 확인:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

| ID | 테스트 항목 | 합격 기준 | 결과 |
|----|------------|---------|------|
| P6-1 | op-geth 실행 | `op-geth` 컨테이너 `Up` 상태, 포트 8545/8546/8551 바인딩 | |
| P6-2 | op-node 실행 | `op-node` 컨테이너 `Up` 상태, 포트 9545/7300 바인딩 | |
| P6-3 | op-batcher 실행 | `op-batcher` 컨테이너 `Up` 상태, 포트 8548 바인딩 | |
| P6-4 | op-proposer 실행 | `op-proposer` 컨테이너 `Up` 상태, 포트 8560 바인딩 (fault proof 비활성 시) | |
| P6-5 | 컨테이너 재시작 없음 | `docker ps` RESTARTS 컬럼 | 모든 L2 컨테이너 재시작 횟수 0 (또는 1 이하) | |

### 6-2. L2 RPC 응답

```bash
# eth_chainId
curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

# eth_blockNumber (몇 초 후 블록 생성 확인)
curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

| ID | 테스트 항목 | 합격 기준 | 결과 |
|----|------------|---------|------|
| P6-6 | L2 RPC 응답 | `eth_chainId` 응답이 L2 체인 ID 반환 (`result` 필드 존재) | |
| P6-7 | 블록 생성 확인 | 30초 대기 후 `eth_blockNumber` 재조회 → 블록 번호 증가 | |
| P6-8 | L1 연결 확인 | op-node 로그: `l1_head` 업데이트 메시지 확인 | |

### 6-3. 프리셋 모듈 (선택, 프리셋에 따라)

```bash
# Bridge (General 프리셋)
curl -s http://localhost:3001

# Blockscout Explorer
curl -s http://localhost:4001

# Grafana Monitoring
curl -s http://localhost:3002
```

| ID | 테스트 항목 | 합격 기준 | 결과 |
|----|------------|---------|------|
| P6-9 | Bridge UI 접근 | `http://localhost:3001` → 브리지 페이지 로드 | |
| P6-10 | Explorer 접근 | `http://localhost:4001` → Blockscout 페이지 로드 | |
| P6-11 | Monitoring 접근 | `http://localhost:3002` → Grafana 로그인 페이지 | |

---

## Phase 7: Desktop App UI 후속 상태

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P7-1 | 대시보드 체인 정보 | 배포 완료 후 대시보드 확인 | L2 RPC URL, L2 Chain ID, 체인 이름 표시 | |
| P7-2 | 인프라 표시 | 스택 상세 화면 | "Local Docker Compose" 또는 동등한 인프라 표시 | |
| P7-3 | 배포 로그 조회 | 스택 → Deployment Logs | deploy-l1-contracts, deploy-aws-infra(local) 단계별 로그 조회 가능 | |
| P7-4 | 스택 상태 Polling | 대시보드 자동 갱신 | 스택 상태 "Deployed" 유지, 주기적 갱신 | |

---

## Phase 8: 에러 시나리오 검증

| ID | 테스트 항목 | 재현 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P8-1 | 잘못된 Sepolia RPC | 존재하지 않는 RPC URL로 배포 | L1 컨트랙트 배포 단계에서 실패, "failed to deploy" 에러 메시지 | |
| P8-2 | Sepolia ETH 부족 | 잔액 없는 Seed Phrase로 배포 | 펀딩 체크 단계에서 경고 표시, 또는 배포 실패 후 명확한 에러 | |
| P8-3 | Docker 미실행 상태 | Docker Desktop 종료 후 로컬 배포 시도 | "deploy-aws-infra" 단계에서 실패, Docker 관련 에러 로그 | |
| P8-4 | 포트 충돌 | 8545 포트 사용 중인 상태에서 배포 | Docker Compose 실행 실패, 포트 충돌 에러 로그 | |
| P8-5 | 재배포(중복) | 동일 chain name으로 재배포 시도 | 중복 배포 방지 에러 또는 기존 스택 재사용 안내 | |

---

## Phase 9: 정리 (Teardown)

| ID | 테스트 항목 | 검증 방법 | 합격 기준 | 결과 |
|----|------------|---------|---------|------|
| P9-1 | 스택 삭제 | Dashboard → Stack → Delete/Destroy | `docker compose down -v` 실행, 모든 L2 컨테이너 종료 | |
| P9-2 | 컨테이너 정리 확인 | `docker ps` 확인 | op-geth, op-node, op-batcher, op-proposer 컨테이너 사라짐 | |
| P9-3 | 볼륨 정리 확인 | `docker volume ls` 확인 | op-geth-data, blockscout-db-data 등 볼륨 제거됨 | |
| P9-4 | 스택 상태 갱신 | 대시보드 확인 | 스택이 대시보드에서 제거되거나 "Terminated" 상태로 전환 | |

---

## 빠른 연기 테스트 (Smoke Test)

> CI/배포 후 핵심 동작만 빠르게 검증하는 최소 항목

```
[ ] P2-5  Local Docker 버튼 클릭 → AWS 섹션 숨김
[ ] P2-7  Local 선택 시 Mainnet 옵션 비활성화
[ ] P3-1  ConfigReview에 "Local Docker Deployment" 카드 표시
[ ] P5-1  배포 요청에 infraProvider: "local" 포함
[ ] P6-1  op-geth 컨테이너 Up 상태
[ ] P6-6  L2 RPC eth_chainId 응답 정상
[ ] P6-7  블록 번호 증가 확인 (30초 대기)
[ ] P9-1  스택 삭제 후 컨테이너 종료
```

---

## 참고 명령어

```bash
# L2 컨테이너 전체 확인
docker ps --filter "name=op-"

# op-geth 로그
docker logs op-geth -f --tail 50

# op-node L1 연결 상태
docker logs op-node -f --tail 50 | grep -i "l1_head\|unsafe\|safe"

# op-batcher 제출 상태
docker logs op-batcher -f --tail 50 | grep -i "batch\|submit"

# L2 블록 생성 모니터링
watch -n 5 'curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" | jq .result'
```

---

*작성일: 2026-03-19*
*대상 버전: trh-platform v2.x (local Docker infra 지원 이후)*
