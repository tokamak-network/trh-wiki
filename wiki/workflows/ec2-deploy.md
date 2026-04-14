---
updated: 2026-04-14
sources:
  - trh-platform/src/main/aws-auth.ts
  - trh-platform/src/main/webview.ts
  - trh-backend/pkg/services/thanos/deployment.go
  - trh-backend/pkg/stacks/thanos/thanos_stack.go
  - trh-sdk/pkg/stacks/thanos/deploy_chain.go
  - trh-sdk/pkg/cloud-provider/aws/aws.go
related:
  - "[[l2-deployment]]"
  - "[[l2-deploy-local]]"
  - "[[architecture]]"
  - "[[trh-platform]]"
  - "[[trh-backend]]"
  - "[[trh-sdk]]"
  - "[[tokamak-thanos-stack]]"
  - "[[presets]]"
  - "[[aws-sso]]"
tags: [workflow]
---

# AWS L2 Deployment (EKS)

trh-platform Desktop App에서 **Infrastructure Provider = AWS** 선택 시 L2 롤업이 배포되는 전체 엔드투엔드 플로우. 로컬 Docker 경로([[l2-deploy-local]])와 달리 L2 노드(op-geth / op-node / op-batcher / op-proposer)는 **AWS EKS 파드**로 실행된다.

**배포 모델**:
- L1 컨트랙트 → 실제 Sepolia/Mainnet (Foundry `start-deploy.sh`)
- L2 인프라 → Terraform(VPC/EKS/EFS/IAM) + Helm 2-pass
- SSH/EC2 user-data 없음, 100% EKS Helm chart

> ⚠️ **이름 주의**: 파일명/route명은 `ec2-deploy` / `deploy-aws-infra`로 남아있으나 **실제 컴퓨트는 EC2가 아닌 EKS 파드**다. 역사적 네이밍이다.

---

## 레이어 맵

```
trh-platform (Electron shell)
   └─ SSO temp creds 획득 → webview JS 글로벌 주입
         │
         ▼
trh-platform-ui (임베디드 Next.js)
   └─ POST /api/v1/stacks/thanos  { infraProvider:"aws", awsAccessKey, ... }
         │
         ▼
trh-backend (Gin + GORM)
   └─ StackEntity INSERT → TaskManager goroutine
         └─ trh-sdk Go module 호출 (exec 아님)
               │
               ▼
trh-sdk
   ├─ DeployContracts → Foundry start-deploy.sh (L1)
   └─ Deploy(ctx, consts.AWS, ...) (L2 infra)
         ├─ AWS SDK (STS, EC2, DynamoDB, S3)
         ├─ terraform init/apply (backend + main stack)
         ├─ aws eks update-kubeconfig
         └─ helm install (pass1: PVC, pass2: workloads)
               │
               ▼
       tokamak-thanos-stack (clone 시점)
         ├─ terraform/backend, terraform/thanos-stack
         └─ charts/thanos-stack
```

---

## 사전 요구사항

| 항목 | 요구사항 |
|------|---------|
| AWS 자격증명 | IAM access key + secret **또는** SSO 로그인(Electron이 temp creds로 변환) |
| AWS 권한 | EC2/EKS/IAM/VPC/EFS/S3/DynamoDB/ELB 생성 가능 |
| 지역 | `trh-sdk`가 `DescribeRegions`로 사전 검증 (trh-backend DTO에서 live 검증) |
| L1 RPC/Beacon URL | Sepolia 또는 Mainnet |
| Seed Phrase | 12단어 BIP39 (BIP44로 admin/sequencer/batcher/proposer 4개 키 파생) |
| L1 ETH | Admin 0.5+, Batcher 0.3+, Proposer 0.3+ (Mainnet은 더 많이) |
| 체인 파라미터 | ChainName, L2BlockTime, BatchSubmissionFreq, OutputRootFreq, ChallengePeriod, EnableFaultProof, FeeToken(`TON|ETH|USDT|USDC`), Preset |
| Mainnet 전용 | `MainnetConfirmation{AcknowledgedIrreversibility, Costs, Risks}` 3개 전부 true |

Mainnet은 **AWS 경로에서만 허용**. Local은 `LocalDevnet` 거부(DTO 레벨 validation).

---

## Phase 1 — Electron 쉘: SSO 자격증명 획득

**역할**: 자격증명 전달자. 실제 배포 HTTP 호출은 임베디드 웹 UI에서 직접 나간다.

### 파일
- `src/main/aws-auth.ts`
- `src/main/index.ts:650-677` (IPC 핸들러 등록)
- `src/main/webview-preload.ts:18-31` (`window.__TRH_DESKTOP__` 브리지)
- `src/main/webview.ts:295-310` (`injectAwsCredentials`)

### 플로우
1. `startSsoLoginDirect` (`aws-auth.ts:335`) — `SSOOIDCClient` 디바이스 코드 등록 → `shell.openExternal(verificationUri)` → 폴링 `CreateTokenCommand` → `ssoAccessToken` 모듈 변수 캐시.
2. `listSsoAccounts` / `listSsoRoles` / `assumeSsoRole` (`aws-auth.ts:389/409/428`) → `GetRoleCredentialsCommand` → `currentCredentials` 인메모리 캐시 (앱 종료 시 휘발, OS keychain/디스크 저장 없음).
3. 웹뷰 네비게이션(`did-finish-load` / `did-navigate` / `did-navigate-in-page`)마다 `injectAwsCredentials`가 `executeJavaScript`로 `window.__TRH_AWS_CREDENTIALS__ = {accessKeyId, secretAccessKey, sessionToken, source}`를 주입.

**중요**: Electron 메인 프로세스는 백엔드에 자격증명을 ENV/IPC로 주입하지 않는다. 경로는 **브라우저 JS 글로벌 → HTTP body** 뿐이다.

---

## Phase 2 — Web UI: Preset 위자드 → 배포 요청

1. 사이드바 → Rollup → Create New Rollup → **Infrastructure Provider: AWS**
2. AWS Configuration 섹션 등장: accessKey/secretKey/region (또는 SSO 후 주입된 temp creds 자동 주입)
3. Network: Testnet/Mainnet 선택, Chain params, Preset, FeeToken, Seed Phrase 입력
4. UI가 `window.__TRH_AWS_CREDENTIALS__`를 읽어 요청 body에 실음

### API 요청

```http
POST /api/v1/stacks/thanos
Authorization: Bearer <admin JWT>
Content-Type: application/json

{
  "infraProvider": "aws",
  "network": "Testnet",
  "awsAccessKey": "...",
  "awsSecretAccessKey": "...",
  "awsRegion": "ap-northeast-2",
  "l1RpcUrl": "...",
  "l1BeaconUrl": "...",
  "chainName": "MyRollup",
  "l2BlockTime": 2,
  "batchSubmissionFrequency": 1500,
  "outputRootFrequency": 240,
  "challengePeriod": 12,
  "enableFaultProof": false,
  "feeToken": "TON",
  "presetId": "DeFi",
  "adminAccount": "...",
  "sequencerAccount": "...",
  "batcherAccount": "...",
  "proposerAccount": "...",
  "seedPhrase": "...",
  "backupConfig": { "enabled": true }
}
```

---

## Phase 3 — trh-backend: 영속화 + 비동기 큐잉

### Route & Handler
- `pkg/api/routes/route.go:187` — `POST /api/v1/stacks/thanos` (admin JWT 보호)
- `pkg/api/handlers/thanos/deployment.go:32` `Deploy`
- DTO: `pkg/api/dtos/thanos.go:56` `DeployThanosRequest`
  - `InfraProvider` (L84) ← 분기 키
  - `AwsAccessKey/SecretAccessKey/Region` (L70–72, `binding:"required"`)
  - `Validate` (L87–183) → `trhSdkAws.IsAvailableRegion(access, secret, region)` 호출로 **live STS/EC2 ping**

### Service
- `pkg/services/thanos/stack_lifecycle.go:20` `CreateThanosStack`
  - 스택 UUID + `deploymentPath` 생성
  - 요청 전체 → `StackEntity.Config` JSON → Postgres (L77)
  - Pending `DeploymentEntity` 2행: `deploy-l1-contracts`, `deploy-aws-infra`
  - L176–178: `taskManager.AddTask("deploy-thanos-stack-<uuid>", func(ctx) { s.deploy(ctx, stackId) })` — **in-process goroutine**, 외부 큐 없음
  - 즉시 `200 {stackId}` 반환

### Async Orchestrator
- `pkg/services/thanos/deployment.go`
  - `deploy` (L31) → `executeDeployments` (L435)
  - L472–497: pending 행을 **L1 → AWS infra 순**으로 강제 정렬
  - Step1 `deploy-l1-contracts` (L556) → `thanos.DeployL1Contracts(...)` (L579)
  - Step2 분기 (L601):
    - `"local"` → `DeployLocalInfrastructure(...)` (L614)
    - `"aws"` → **`DeployAWSInfrastructure(...)`** (L620)
  - 로그 테일링: `go s.tailAndIngestDeploymentLogs(...)` (L577,610)
  - 완료 후 `ShowChainInformation` → `StackMetadata` 저장(L1/L2 chainId, RPC, bridge/explorer/monitoring URL)

### SDK 래퍼
- `pkg/stacks/thanos/thanos_stack.go`
  - `NewThanosSDKClient` (L18): `thanosTypes.AWSConfig{AccessKey, SecretKey, Region}` → `thanosStack.NewThanosStack(...)` (L45)
  - `DeployL1Contracts` (L129) → `sdkClient.DeployContracts(...)` (L166)
  - `DeployAWSInfrastructure` (L58) → **`sdkClient.Deploy(ctx, consts.AWS, &input)`** (L75)

> 📌 **trh-backend는 trh-sdk를 Go module로 직접 import** (`go.mod:15`). `exec.Command("trh-sdk")` 셸아웃 **아님**. 모든 AWS SDK v2 모듈(`sts`/`ec2`/`dynamodb`/`s3`/`efs`/`backup`/...)은 trh-sdk의 indirect dependency.

---

## Phase 4 — trh-sdk: L1 컨트랙트 배포

**Local/AWS 공통 경로** — Foundry 셸아웃.

파일: `pkg/stacks/thanos/deploy_contracts.go:33` `DeployContracts`

1. `tokamak-thanos` 레포 clone (`input.go:1906` `cloneSourcecode`, L145/L237)
2. `ethclient`로 Admin nonce 안정화 대기 (L617–649) — Go native
3. `.env` 생성: `GS_ADMIN_PRIVATE_KEY`, `L1_RPC_URL`, `GAS_PRICE` (L656–665)
4. `patchStartDeployScript` (L724): `start-deploy.sh` in-place 패치
   - fault-proof off면 cannon 스킵
   - `make op-node` → 직접 `go build`
   - TS core-utils/SDK 빌드 스킵
5. **Foundry 셸아웃** (L699):
   ```bash
   bash ./start-deploy.sh deploy -e .env -c deploy-config.json
   ```
   → `OptimismPortal`, `SystemConfig`, `L2OutputOracle`, `AnchorStateRegistry` 등 L1 배포
6. 산출물:
   - `<L1ChainID>-deploy.json` (contract addresses)
   - `tokamak-thanos/build/genesis.json`
   - `tokamak-thanos/build/rollup.json`
   - `settings.json`
7. 후처리: `rollup.json` genesis hash 패치 (L1088–1140), fault-proof 시 `AnchorStateRegistry.sol` 패치 + `initGenesisAnchorState`(go-ethereum guardian tx)

---

## Phase 5 — trh-sdk: AWS 인프라 배포

파일: `pkg/stacks/thanos/deploy_chain.go:30` `Deploy` → `switch infraOpt` → `deployNetworkToAWS` (L140)

### 5a. 사전 준비
- `tool_readiness.go:33`: `terraform`/`aws-cli`/`kubectl`/`helm` 병렬 설치 확인
- `pkg/cloud-provider/aws/aws.go` (단일 파일 270줄):
  - `credentials.NewStaticCredentialsProvider` (L103) — **Static access/secret만 지원**. SSO/AssumeRole 내장 없음 (Electron의 temp creds는 session token 포함한 static creds로 취급 → 정상 동작)
  - STS `GetCallerIdentity` (L112) — account/ARN 검증
  - EC2 `DescribeAvailabilityZones` (L162), `DescribeRegions` (L248)
  - DynamoDB `ListTables` + `CreateTable` (L196, L208) → **`terraform-lock` 테이블 부트스트랩**
  - 키를 `os.Environ` export (L83–86) → 이후 모든 `terraform`/`aws`/`kubectl`/`helm` 서브프로세스가 상속
- `tokamak-thanos-stack` 레포 clone (L168)

### 5b. Terraform 2-stage (bash -c 셸아웃)
`makeTerraformEnvFile` (L240)이 `.envrc` 생성 → 매 tf 호출 전 `source`.

1. **Backend 부트스트랩** (L307–316): `terraform/backend`
   - S3 bucket (state)
   - DynamoDB (lock) 원격 백엔드
2. **Main stack** (L324–332): `terraform/thanos-stack`
   - VPC, EKS 클러스터, IAM role/policy, EFS (영속 볼륨), ALB/Ingress Controller
   - Helm chart용 `thanos-stack-values.yaml`도 이때 렌더
3. `terraform output -json vpc_id` (L339–345) → `settings.json`

### 5c. Kubeconfig + Helm 2-pass
- `SetAWSConfigFile` / `SetAWSCredentialsFile` / `SetKubeconfigFile` / `SwitchKubernetesContext` (L374–386)
- `CheckK8sReady` (L394)
- `helm repo add thanos-stack https://tokamak-network.github.io/tokamak-thanos-stack` (L408)
- **Pass 1** (L437–442): `enable_vpc=true` → PVC 먼저 생성 → `WaitPVCReady` (L449)
- **Pass 2** (L456–461): `enable_deployment=true` → `op-geth` / `op-node` / `op-batcher` / `op-proposer` (+ 옵션 `op-challenger`) 파드 롤아웃
- 이미지 태그: `constants.DockerImageTag[network].{ThanosStackImageTag, OpGethImageTag}` (L253–254)
- RPC URL 발견: `utils.GetAddressByIngress` 폴링 (L471–483) → `http://<ingress-host>`

**왜 2-pass인가**: EFS PVC가 파드보다 먼저 Bound 상태가 되어야 op-geth가 볼륨 마운트에 실패하지 않기 때문. 단일 helm install로는 race가 발생.

### 5d. Preset 모듈 레이어링
`deploy_chain.go:561–590` — preset에 따라 조건부:

| 모듈 | AWS 동작 | Local 동작 |
|------|---------|-----------|
| `uptimeService` | 자동 `InstallUptimeService` (terraform + Helm) | 자동 |
| `monitoring` | **사용자 수동 `trh install monitoring`** | 자동 compose profile |
| `blockExplorer` | **사용자 수동 `trh install block-explorer`** | 자동 compose |
| `crossTrade` | **사용자 수동 `trh install cross-trade`** | 자동 compose + `cross_trade_local.go` |
| `drb` (genesis) | L2 genesis allocs 주입 (`drb_genesis.go`) | 동일 |
| `aaPaymaster` | Helm chart 내부에서 기동 | Go `setupAAPaymaster` 호출 |

---

## Phase 6 — 결과 반영

- trh-sdk가 `settings.json`에 L2 RPC URL / VPC ID / chainId 등 영속화
- trh-backend `deploy()`가 `ShowChainInformation` 재호출 → `StackMetadata` 업데이트
- `DeploymentEntity.Status` → `completed`, Next.js 대시보드 폴링이 감지

---

## 배포 완료 검증

```bash
# EKS 컨텍스트 전환
aws eks update-kubeconfig --region <region> --name <cluster>

# 파드 상태
kubectl -n <namespace> get pods
# 기대: op-geth-0, op-node-0, op-batcher-0, op-proposer-0 전부 Running

# Ingress 주소 확인
kubectl -n <namespace> get ingress

# L2 RPC 응답
curl -s -X POST http://<ingress-host> \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'

# 블록 생성 확인
curl -s -X POST http://<ingress-host> \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

---

## 정리 (Teardown)

Dashboard → Stack → Delete → trh-backend가 `thanos.DestroyAWSInfrastructure` 호출 → trh-sdk `destroyInfraOnAWS`:
1. `terraform destroy` (thanos-stack → backend 순)
2. DynamoDB `terraform-lock` 테이블 삭제
3. S3 state 버킷 비우고 삭제
4. Stack/DeploymentEntity → `terminated`

---

## Local vs AWS 비교

| 단계 | Local Docker | AWS EKS |
|---|---|---|
| 오케스트레이터 | docker-compose | Terraform + Helm + kubectl |
| 추가 clone | 없음 | **`tokamak-thanos-stack`** |
| L1 컨트랙트 | Foundry `start-deploy.sh` | 동일 |
| L2 노드 | 로컬 Docker 컨테이너 | **EKS 파드 (Helm 2-pass)** |
| 네트워킹 | `localhost:8545`... | **EKS Ingress `http://<host>`** |
| Network | Sepolia only (LocalDevnet 거부) | Sepolia + Mainnet |
| State lock | 없음 | **DynamoDB `terraform-lock`** |
| AA Paymaster | Go가 setup 호출 | Helm chart 내장 |
| Backup | n/a | EFS + backup manager |
| Cleanup | `docker compose down -v` | `terraform destroy` + S3/Dynamo 정리 |

---

## 알려진 함정 & 기술부채

1. **DTO 불일치** — `DeployThanosRequest` (`dtos/thanos.go:70-72`)는 `InfraProvider="local"`에서도 AWS 필드를 `binding:"required"`로 요구. 조건부 검증은 `PresetDeployRequest.ValidateProvider` (L560)에만. 신규 클라이언트는 `POST /preset-deploy`를 쓰고, 구 경로는 항상 AWS 필드를 더미로 채워야 함.
2. **평문 저장** — AWS creds가 `StackEntity.Config` JSON에 평문 (`stack_lifecycle.go:77`). KMS/envelope encryption 없음. DB 덤프가 곧 AWS 권한 노출.
3. **SSO 세션 리프레시 부재** — Electron SSO role creds는 보통 1h TTL. `webview.ts`에 리프레시 로직이 없어 장시간 `terraform apply` 중 세션 만료 시 silent fail. 현재는 사용자가 재로그인 후 재배포.
4. **SDK 레벨 SSO 미지원** — `aws.go:103`은 `NewStaticCredentialsProvider`만 사용. Electron이 넘긴 temp creds는 session token 포함한 static creds로 취급되어 동작하지만, SDK 단독 실행 시 SSO 흐름 없음.
5. **웹뷰 JS 글로벌 노출** — `window.__TRH_AWS_CREDENTIALS__`는 웹 컨텍스트의 **모든 스크립트에 읽힘**. `hidePlatformView`에서도 클리어 안 됨. IPC getter(`awsGetCredentials`)가 있음에도 사용하지 않음.
6. **백엔드 컨테이너 ENV 비어있음** — Electron이 띄우는 `trh-backend` 컨테이너는 AWS ENV 없이 기동. `~/.aws/credentials` 기반 배포는 Electron 경유로 불가능 (요청 body만).
7. **Preset 모듈 반자동** — AWS에서 monitoring/blockExplorer/crossTrade는 메인 deploy 이후 수동 `trh install <X>`. 로컬 경로와 비대칭.
8. **Naming 잔재** — `deploy-aws-infra` / `ec2-deploy`라는 이름이 남아있으나 실제 컴퓨트는 EKS. 역사적 네이밍.
9. **TerminateThanosRequest DTO dead code** — `dtos/thanos.go:247`의 terminate DTO가 AWS 필드를 요구하지만 실제 terminate 핸들러는 UUID path param만 사용.

---

## 핵심 파일 레퍼런스

### trh-platform
- `src/main/aws-auth.ts` — 전체 SSO 플로우 (1–457)
- `src/main/index.ts:650-677` — AWS IPC 핸들러 등록
- `src/main/preload.ts:163-173` — 렌더러 AWS API 서페이스
- `src/main/webview-preload.ts:18-31` — `window.__TRH_DESKTOP__` 브리지
- `src/main/webview.ts:295-310` — 자격증명 주입; L137/150/174 re-inject 트리거

### trh-backend
- `pkg/api/routes/route.go:187` — `POST /api/v1/stacks/thanos`
- `pkg/api/handlers/thanos/deployment.go:32` — `Deploy` 핸들러
- `pkg/api/dtos/thanos.go:56` — `DeployThanosRequest`, L87 `Validate`
- `pkg/services/thanos/stack_lifecycle.go:20` — `CreateThanosStack`, L176 enqueue
- `pkg/services/thanos/deployment.go:31` — `deploy`, L435 `executeDeployments`, L579 L1 호출, L620 AWS infra 호출
- `pkg/stacks/thanos/thanos_stack.go:18` — `NewThanosSDKClient`, L58 `DeployAWSInfrastructure`, L129 `DeployL1Contracts`
- `pkg/services/task_manager.go` — in-process goroutine 레지스트리
- `go.mod:15` — `github.com/tokamak-network/trh-sdk`

### trh-sdk
- `cli.go`, `commands/deploy.go`
- `pkg/stacks/thanos/deploy_chain.go` — `Deploy` L30, `deployNetworkToAWS` L140, terraform 셸아웃 L307/324/339, Helm 2-pass L437/456
- `pkg/stacks/thanos/deploy_contracts.go` — `DeployContracts` L33, Foundry invoke L699
- `pkg/stacks/thanos/tool_readiness.go:33` — `{terraform, aws-cli, kubectl, helm}`
- `pkg/stacks/thanos/input.go:1906` — `cloneSourcecode`
- `pkg/cloud-provider/aws/aws.go` — 단일 파일 AWS SDK 래퍼
- `pkg/stacks/thanos/{cross_trade,monitoring,block_explorer,uptime_service,drb_genesis,aa_setup}.go` — preset 모듈

### tokamak-thanos-stack (배포 시점에 clone)
- `terraform/backend/*.tf` — S3 + DynamoDB 원격 상태
- `terraform/thanos-stack/*.tf` — VPC/EKS/EFS/IAM/Ingress
- `terraform/thanos-stack/thanos-stack-values.yaml` — Helm values (terraform 렌더)
- `charts/thanos-stack/*` — op-geth/op-node/op-batcher/op-proposer 템플릿
- `charts/cross-trade/*` — CrossTrade Helm chart
