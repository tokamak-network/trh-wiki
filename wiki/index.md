---
updated: 2026-05-07 (structure simplified)
---

# TRH Wiki Index

Master index of all wiki pages. Updated on every ingest operation.

---

## Components

| Page | Summary |
|------|---------|
| [[architecture]] | Full system architecture map — 4 repos, their roles, and how they connect |
| [[thanos-deployer-analysis]] | Complete deployment logic analysis — 8-layer architecture, 6-phase flow, 51 functions, critical pitfalls |
| [[trh-platform]] | Electron desktop app — main/renderer/preload architecture, IPC patterns |
| [[trh-sdk]] | Go CLI deployment engine — preset configs, L2 deployment orchestration |
| [[trh-backend]] | Go REST API — Gin + GORM, endpoints, Docker lifecycle management |
| [[trh-platform-ui]] | Next.js web frontend — embedded in Electron WebContentsView |
| [[tokamak-thanos]] | OP Stack v1.7.7 포크 — op-node, op-batcher, op-proposer, 컨트랙트, TypeScript SDK |
| [[tokamak-thanos-stack]] | Terraform + Helm IaC — AWS EKS 인프라, 체인 노드 K8s 배포 |
| [[tokamak-thanos-geth]] | go-ethereum OP Stack 포크 — L2 실행 계층, Deposit TX, Engine API |
| [[tokamak-rollup-hub-v2]] | Rollup Hub 마케팅 웹사이트 — 제품 허브, TRH Desktop 릴리즈 연동 |
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
| [[tokamak-cryptoeconomics]] | TON 시뇨리지, 스테이킹 V1/V2, 검증자의 딜레마, 빠른 출금 — L2 경제 설계 전문 |

## Workflows

| Page | Summary |
|------|---------|
| [[local-dev]] | 레포별 개발 서버 기동, 환경 변수, mock 패턴 |
| [[l2-deploy-local]] | Full walkthrough: deploying an L2 chain locally via Docker Compose |
| [[integration-install]] | Bridge / Block Explorer / Monitoring / CrossTrade 사후 설치 API — curl 예제 + 필드 설명 |
| [[ec2-deploy]] | AWS EC2 deployment via Terraform — one-time setup and update flow |
| [[release]] | Electron DMG/NSIS/AppImage 빌드, Docker 이미지 배포, 버전 고정 패턴 |
| [[testing]] | 테스트 스택, 실행 명령어, E2E 3가지 모드, Vitest/Playwright 패턴 |
| [[drb-deploy]] | trh-sdk DRB 노드 AWS 배포 — EKS leader, EC2 regular, 보안 결정, 브랜치 고정 이유 |
| [[thanos-sepolia-testnet]] | Live Thanos Sepolia Testnet — public endpoints, L1 contracts, fault proof config (deployment 8671124e, L2 chain ID 111551132354) |

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
| [[block-explorer-update-pattern]] | Block Explorer 사용자 설정 변경 = `helm upgrade` 별도 경로(PUT) — Install 멱등성 유지 + DB cred 자동 복원 |
| [[concurrent-deployment-guard]] | 동시 배포 차단 — checkNoActiveDeployingStack(), LocalDevnet 면제, UI guard, L1 nonce conflict 방지 |

## Troubleshooting

| Page | Summary |
|------|---------|
| [[port-conflicts]] | Port conflict detection, resolution, and prevention |
| [[l1-gas-limits]] | L1 gas limit tuning for OptimismPortal deposit transactions |
| [[docker-health-checks]] | Backend health check timeouts and retry strategies |
| [[l2-deposit-verification]] | Verifying L2 deposit transaction execution — polling strategy |
| [[l1-deposit-tx-pitfalls]] | L1 Deposit Tx CrossTrade 배포 시 13개 주요 함정과 방지법 |
| [[cross-trade-deposit-verification-timeout]] | sequencer_l1_confs=5 → 72s 구조적 지연 → 120s timeout 실패 원인 & 300s 증가 |
| [[l2tol2-cross-trade-l1-set-chain-info-missing]] | AWS auto-install에서 L2toL2CrossTradeL1.setChainInfo 누락 → L2→L2 브릿지 revert, trh-sdk 8aba331에서 수정 |
| [[tokamak-deployer-logging]] | Debugging contract deployment hangs via comprehensive logging (v1.0.1+) |
| [[tokamak-deployer-gas-price]] | Fixed gas price reuse strategy (v0.0.5+) — 5m47s measured on Sepolia, 0 retries |
| [[drb-local-compose-path-template-bugs]] | DRB gaming preset 로컬 배포 시 드러난 5개 경로·템플릿 버그 (path, FuncMap, range-scope, PORT, op-geth volume) |
| [[forge-l2genesis-silent-slow]] | forge L2Genesis 단계 로그 무음·과도 지연 — Infow 오용, CombinedOutput, 불필요 --rpc-url |
| [[fcu-v3-post-cancun-rejected]] | forkchoiceUpdatedV3가 Prague/Isthmus 블록 거부 → L2 block 0 stuck — `!= Cancun` → `< Cancun` 수정 |
| [[forge-l2genesis-implementations-object]] | tokamak-deployer v0.0.10 `implementations` 중첩 오브젝트 → forge vm.parseJsonAddress revert → `<empty revert data>` |
| [[l2-output-oracle-uninitialized]] | tokamak-deployer가 L2OutputOracle initialize() 미호출 → proposer=address(0) → op-proposer 제출 실패 |
| [[op-node-pectra-blob-base-fee]] | op-node l1_block_info.go가 CalcBlobFeeCancun 고정 사용 → post-Pectra Sepolia에서 ~10^25 wei blobBaseFee → drb-regular insufficient funds |
| [[delayed-weth-proxy-empty]] | tokamak-deployer v0.0.6이 DelayedWETH를 배포하지 않아 initDisputeGameFactory 실패 → v0.0.7에서 steps 33-35 추가로 수정 |
| [[asr-dgf-proxy-address-bug]] | tokamak-deployer step 31이 ASR constructor에 DGF 구현체 주소 전달 → resolve() 항상 UnregisteredGame() revert → 프록시 주소로 수정 |
| [[optimism-portal-proxy-uninitialized]] | tokamak-deployer가 OptimismPortalProxy initialize() 미호출 → systemConfig=0 → depositTransaction() _metered() revert → CrossTrade L2 배포 실패 |
| [[elb-dns-propagation-delay]] | AWS ELB 생성 후 공개 DNS 전파 지연(~12분) — 권위 NS 직접 쿼리로 우회 (trh-sdk ca84863) |
| [[aws-stage-b-provisioning-optimization]] | Stage B ALB 프로비저닝 대기 최적화 — probe 튜닝, ALB annotation, NS 캐시, errgroup 병렬화로 41min→~30min |
| [[destroy-namespace-timeout]] | AWS destroy 시 `kubectl delete namespace` 가 5분 timeout — finalizer 자가복구 부재 + EFS MT 정리 순서 결함 + Conditions 타입 버그, trh-sdk 4099570에서 자가복구 5단계로 수정 |
| [[block-explorer-envrc-thanos-stack-name-stripped]] | `makeBlockExplorerEnvs`가 .envrc에서 `TF_VAR_thanos_stack_name`을 strip 후 빈 StackName이면 미복구 → block-explorer terraform plan이 stdin 프롬프트로 무한 hang. trh-sdk f6f2f92에서 caller 명시 + 함수 방어로 수정 |
| [[stage-b-backend-config-changed]] | Stage B `terraform init`이 "Backend configuration changed" 실패 — namespace 랜덤 재생성 + 빈 bucket name 2가지 원인. trh-sdk 1f58eee에서 `.terraform/terraform.tfstate`에서 복원하도록 수정 |
| [[aws-deploy-logs-not-visible]] | AWS 인프라 배포 LogDialog "No logs available" — 단일 공유 SDK 클라이언트가 l1Step.LogPath만 기록 → awsStep ingestion goroutine 영구 블로킹. trh-backend 958d898에서 수정 |
| [[terraform-destroy-secretsmanager-backend]] | `terraform destroy` 실패 — secretsmanager child module에 `backend "s3" {}` 블록 선언 → Terraform 1.x 금지. tokamak-thanos-stack 1dd0d70에서 제거, 수동 복구 절차 포함 |
| [[eip7702-prague-not-set-in-l2-genesis]] | NewL2Genesis()가 PragueTime 미설정 → txpool이 EIP-7702 type 4 tx "pool not yet in Prague"로 거부 — IsthmusTime과 PragueTime은 별개 필드, tokamak-thanos 0e66bf4에서 수정 |
| [[genesis-rollup-hash-mismatch]] | `maybeFundAAAdmin`의 alloc 패치가 block 0 해시를 바꾸지만 rollup.json 미갱신 → op-node CrashLoopBackOff. Stage B preflight check(trh-sdk 18fc5d4)로 자동 재동기화 |
| [[local-testnet-missing-deploy-contracts-step]] | local+Testnet 배포 시 deploy-l1-contracts 스텝 누락 — InfraProvider 조건 오류, Network 기준으로 수정 (trh-backend 351cebb) |
| [[blockscout-wrong-coin-price]] | 로컬 Blockscout에서 TON이 $25 표시 — CoinGecko 심볼 "TON" 충돌(5개 코인), EXCHANGE_RATES_COINGECKO_COIN_ID 누락. trh-sdk 5a74242에서 수정 |
| [[host-docker-internal-linux]] | Linux에서 `host.docker.internal` DNS 미등록 → L2 genesis 블록 대기 실패("no such host") — `extra_hosts: host-gateway` 누락, trh-platform d5929a1에서 수정 |
| [[docker-exec-container-name]] | `docker exec`는 이미지 이름이 아닌 컨테이너 이름 필요 — Docker Compose 생성 규칙 `{project}-{service}-{replica}`, EFP-04 실패 원인 |

---

*Pages listed here but not yet created are stubs — run `lint` to see the full list.*
