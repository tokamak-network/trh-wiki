# Wiki Log

Append-only chronological record of all wiki operations.

Parse the last 5 entries: `grep "^## \[" wiki/log.md | tail -5`

---

## [2026-04-09] init | Wiki initialized
Pages created: [[index]]
Schema defined: CLAUDE.md
Note: All component/concept/workflow/decision/troubleshooting pages are stubs pending first ingest.

## [2026-04-09] ingest | trh-platform/docs/ (Phase 2 migration)
Sources added to raw/architecture/:
  tech-stack.md, presets-implementation.md, local-l2-deployment-test-guide.md,
  e2e-deployment-test-guide.md, preset-deployment-flow.html, trh-deployment-flow.html,
  crosstrade-deploy-flow.html, install-guide.html

Pages created:
  [[architecture]], [[trh-platform]], [[trh-sdk]], [[trh-backend]], [[trh-platform-ui]],
  [[presets]], [[l2-deployment]], [[keystore]], [[l2-deploy-local]],
  [[sequential-l2-deploy]], [[port-conflicts]], [[l1-gas-limits]]

Pages still stub (raw source 없음):
  [[docker-health-checks]], [[l2-deposit-verification]]

## [2026-04-09] ingest | crossTrade/ (CrossTrade integration)
Sources added to raw/decisions/:
  PRD-CrossTrade-TRH-Integration-v2.1.md, Genesis-Predeploy-Storage-Analysis.md

Pages created:
  [[cross-trade]], [[deposit-tx]],
  [[deposit-tx-vs-genesis-predeploy]], [[abigen-vs-manual-calldata]],
  [[separate-compose-for-crosstrade]]

Key facts captured:
  - CrossTrade: DeFi/Full Preset만 (Gaming 제외 — PRD v2.1 수정사항)
  - L2 컨트랙트 배포: L1 Deposit Tx (12 트랜잭션, ~5분)
  - Genesis Predeploy 거부: constructor 미실행 + 15개 스토리지 슬롯 수동 계산 필요
  - ABI 패턴: abigen (OptimismPortal 직접 호출) + abi.Pack (L2 calldata)
  - dApp: docker-compose.crosstrade.yml 별도 파일 (v3.8 호환)

## [2026-04-09] ingest | Thanos 인프라 레포 3종 추가
Sources: 각 레포 소스 코드 직접 탐색 (raw source 없음)

Pages created:
  [[tokamak-thanos]], [[tokamak-thanos-stack]], [[tokamak-thanos-geth]]

Pages updated:
  [[architecture]] — Thanos 인프라 레이어 추가, 데이터 흐름 다이어그램 확장,
                     Shared Technology 테이블 확장, EKS 배포 타겟 추가
  [[index]] — Thanos 인프라 서브섹션 신설

Key facts captured:
  - tokamak-thanos: OP Stack v1.7.7 포크, Go 1.24 + TS 5.4.5, Nx 모노레포
  - tokamak-thanos-stack: Terraform + Helm IaC, EKS + 6개 Helm 차트
  - tokamak-thanos-geth: go-ethereum v1.16.3 포크, Deposit TX (0x7E), Engine API 8551
  - 전체 7개 레포 아키텍처 맵 완성

## [2026-04-09] ingest | 신규 레포 4종 추가 (integration 3 + core 1)
Sources: 각 레포 소스 코드 직접 탐색

Pages created:
  integration/ → [[thanos-bridge]], [[commit-reveal2]], [[drb-node]]
  core/ → [[tokamak-rollup-hub-v2]]

Pages updated:
  [[index]] — Core/Integration 서브섹션 재구성, 4개 신규 항목 추가

Key facts captured:
  - thanos-bridge: Next.js 15 DApp, @tokamak-network/thanos-sdk 0.0.14-dev, Wagmi/Viem
  - commit-reveal2: Solidity 0.8.30, Foundry, 2단계 Commit-Reveal, last revealer attack 방지
  - drb-node: Go 1.23, libp2p, Leader/Regular 2노드 아키텍처, PostgreSQL 영속성
  - tokamak-rollup-hub-v2: Next.js 16 마케팅 사이트, Three.js 3D, GitHub API로 trh-platform 릴리즈 조회

## [2026-04-09] ingest | .planning/ → trh-wiki (CrossTrade 프로젝트 지식 이전)
Sources added to raw/:
  raw/architecture/deployment-pitfalls.md  ← .planning/research/PITFALLS.md
  raw/architecture/testing-guide.md        ← .planning/codebase/TESTING.md

## [2026-04-16] ingest | tokamak-deployer v1.0.1 logging improvements
Sources: tokamak-thanos feat/tokamak-deployer branch

Pages created:
  [[tokamak-deployer-logging]] — Comprehensive logging for debugging contract deployment hangs

Pages updated:
  [[index]] — Added tokamak-deployer-logging to Troubleshooting section

Key facts captured:
  - tokamak-deployer v1.0.0 had zero logging, making hangs undiagnosable
  - v1.0.1 adds 50+ log statements across two levels:
    * High-level: step progress (Step X/32), deployer address, L1 RPC connection
    * Low-level: transaction hashes, gas prices, block confirmations, deployed addresses
  - Enables root cause analysis of deployment hangs and silent failures
  - trh-sdk version pinned updated from v1.0.0 to v1.0.1
  raw/decisions/tech-debt-and-risks.md     ← .planning/codebase/CONCERNS.md
  raw/decisions/requirements-v1.md         ← .planning/REQUIREMENTS.md

Pages created:
  [[l1-deposit-tx-pitfalls]] — L1 Deposit Tx CrossTrade 배포 13개 함정 (Critical/Moderate/Minor)
  [[testing]] — Vitest + Playwright 테스트 스택, 3가지 E2E 모드, 핵심 패턴
  [[tech-debt-and-risks]] — Known bugs, security concerns, dependencies at risk, test coverage gaps
  [[requirements-v1]] — CrossTrade 통합 v1 요구사항 30개 + Phase traceability

Pages updated:
  [[index]] — Workflows, Decisions, Troubleshooting 섹션에 5개 신규 항목 추가

.planning 정리:
  삭제: research/, codebase/, phases/01~04/, quick/, debug/, REQUIREMENTS.md
  유지: phases/05/ (E2E Phase 미완료), PROJECT.md, ROADMAP.md, STATE.md

## [2026-04-09] refactor | raw/ 드롭존 구조 개편
HTML 다이어그램 에셋 분리 및 inbox/ 드롭존 추가

Files moved:
  raw/architecture/*.html (4개) → raw/assets/

New directories:
  raw/inbox/     ← 신규 문서 드롭존 (분류 전 보관)
  raw/assets/    ← HTML 다이어그램 및 이미지 에셋

CLAUDE.md 업데이트:
  - raw/ 디렉토리 레이아웃 설명 갱신
  - inbox/ 드롭존 워크플로우 명시
  - wiki/components/ core/integration 서브섹션 반영
  - 컴포넌트 canonical names 12개 레포로 확장

## [2026-04-11] update | CrossTrade E2E 테스트 스위트 완성 반영
Pages updated:
  [[testing]] — CrossTrade Live TX 테스트 섹션 신설 (CRT-01~07 전체 통과 기록),
               EIP-6963 mock provider 주입 패턴 추가,
               crosstrade-tx.live.spec.ts 파일 구조에 추가
  [[cross-trade]] — E2E 테스트 섹션 신설 (테스트 ID × 컨트랙트 대응 테이블, 가스 정책)
  [[l1-gas-limits]] — provideCT 관련 행 2개 추가 (auto estimation),
                      "explicit gasLimit 제거 배경" 섹션 신설

Key facts captured:
  - CRT-01~07 전체 통과 (2026-04-11)
  - L1 provideCT gasLimit: explicit 제거 → ethers.js 자동 추정 (commit: 8ec40d8)
  - L2-L2 provideCT: CDM 2회 overhead → ~800k (explicit 제거 후 자동 추정으로 해결)
  - CRT-07: EIP-6963 eip6963:announceProvider 이벤트로 mock wallet 주입 패턴 확립
  - _minGasLimit 파라미터(CDM relay용 200k)는 L1 TX gasLimit과 별개

## [2026-04-10] ingest | raw/inbox/crosstrade-deployment-guide.md
Source: crossTrade/docs/deployment-guide.md (Foundry 기반 배포 가이드)

Pages updated:
  [[cross-trade]] — 운영 함정 섹션 추가 (admin key 잠김, L2-L2 proxy-direct setChainInfo 함정)
  [[l1-deposit-tx-pitfalls]] — Pitfall #14 추가 (upgradeTo 없이 setChainInfo만 성공하는 silent broken 상태)

Pages deleted:
  [[crosstrade-deployment]] — raw 재포맷에 불과, 비자명한 인사이트만 기존 페이지에 흡수

Key facts captured (비자명한 것만):
  - Admin key 없으면 기존 프록시에 새 체인 영구 등록 불가 → 재배포 필요. 사전에 isAdmin() 확인 필수.
  - L2toL2CrossTradeProxy.setChainInfo는 proxy-direct 구현 → implementation() == 0x0에서도 성공. 나머지 함수는 impl 위임 → silent broken 상태 가능.
  - 실제 발생: ect-defi L2toL2CrossTradeProxy(0x2452ceB6...) 이전 세션에서 setChainInfo 성공했으나 upgradeTo 미실행 → chainData() revert로 뒤늦게 발견.

## [2026-04-13] ingest | thanos-bridge 로컬 Docker 배포 트러블슈팅
Sources added to raw/sessions/:
  debug-network-switch-failure-on-local-bridge-withdraw.md
  debug-env-vars-not-applied-localhost-3001-bridge.md
  debug-bridge-info-data-truncated-with-ellipsis.md
  debug-withdraw-network-switch-balance-zero.md

Pages created:
  [[thanos-bridge-local-docker-deployment]] — 로컬 Docker 배포 시 발생하는 4가지 문제 트러블슈팅

Key facts captured:
  - next-runtime-env는 빌드 타임이 아닌 런타임에 NEXT_PUBLIC_* 읽음 → Next.js standalone 모드에서 docker run -e 플래그 필수
  - host.docker.internal은 컨테이너 내부에서만 동작, 브라우저(wagmi)에서는 localhost 사용 필요
  - isHTTPS() 유틸: localhost / 127.0.0.1 / host.docker.internal 모두 허용 (useNetwork.ts에서 사용)
  - BridgeInfoItem truncate 버그: Chakra UI truncate prop + maxWidth 제거로 수정

## [2026-04-14] ingest | workflows/ec2-deploy.md (AWS L2 deploy flow)
Sources: trh-platform/src/main/{aws-auth,webview,webview-preload,index}.ts,
         trh-backend/pkg/{api,services,stacks}/thanos/*,
         trh-sdk/pkg/{stacks/thanos,cloud-provider/aws}/*

Page filled: [[ec2-deploy]] (replaces 2026-04-09 stub)
Scope: 6-Phase 전체 경로 — Electron SSO creds 획득 → Next.js POST → trh-backend goroutine (TaskManager) → trh-sdk Foundry L1 deploy → trh-sdk Terraform+Helm 2-pass on EKS

Key facts captured:
  - Electron은 "자격증명 전달자"일 뿐. 실제 배포는 임베디드 Next.js UI → localhost:8000 HTTP 직통.
  - 자격증명 전달 경로: SSO temp creds → window.__TRH_AWS_CREDENTIALS__ JS 글로벌 → POST body
  - trh-backend는 trh-sdk를 Go 모듈로 import (셸아웃 아님). in-process goroutine으로 순차 실행.
  - trh-sdk AWS 경로: Foundry(L1) → Terraform 2단계(S3+DynamoDB backend, VPC+EKS+EFS) → Helm 2-pass(PVC → workloads) → ingress 폴링
  - SSH/raw EC2 없음. 모든 L2 노드는 EKS Helm 파드. "ec2-deploy" 명칭은 레거시.
  - Gotchas: AWS creds Postgres 평문 저장, SSO 토큰 리프레시 없음(1h TTL), DTO required-field 비일관성, trh-sdk static creds only

## [2026-04-15] housekeeping | aws-sso 삭제 + 미작성 페이지 3종 ingest
Pages deleted: [[aws-sso]] (참조 5곳 제거 — keystore, index, ec2-deploy, trh-platform×2)
New pages: [[docker-compose-lifecycle]], [[local-dev]], [[release]]
Key additions:
  - docker-compose-lifecycle: Preset별 compose file 분기, 컨테이너 포트 목록, 레이어 구조
  - local-dev: 레포별 개발 서버 기동법, VITE_MOCK_ELECTRON/ELECTRON_USE_BUILD 환경 변수
  - release: Electron DMG/NSIS/AppImage 빌드 타겟, GitHub Releases 연동, Docker Hub 패턴

## [2026-04-15] update | trh-platform-ui Preset Wizard 2-step 간소화
Pages updated: [[trh-platform-ui]]
Changes:
  - 배포 위자드 플로우: Preset Mode 4-step → 2-step (Step1: Preset 선택, Step2: Basic Info & Deploy)
  - 입력 필드: 26개 → 5개 (presetId, chainName, network, awsAccessKey, awsSecretKey)
  - 제거 항목: seedPhrase, l1RpcUrl, l1BeaconUrl, feeToken, infraProvider, reuseDeployment, awsRegion
  - Classic Mode(4-step) 설명 추가 (기존 유지)
Key decision: 시스템이 L1 인프라 및 계정 설정 자동 결정 → 사용자 입력 최소화 (docs/preset-deploy-prd.md 기반)

## [2026-04-15] ingest | DRB-node + Commit-Reveal2 repo analysis
Pages updated: [[drb-node]], [[commit-reveal2]], [[index]]
New pages: [[drb-project]]

## [2026-04-15] ingest | op-batcher blob fee spike fix
New pages: [[op-batcher-blob-fee-spike]] (troubleshooting/)

## [2026-04-15] ingest | preset-deploy 409 트러블슈팅
New pages: [[preset-deploy-409]] (troubleshooting/)
Pages updated: [[l2-deploy-local]] — 알려진 이슈 섹션에 [[preset-deploy-409]] 링크 추가
Code fix: trh-platform-ui/src/features/rollup/hooks/usePresetWizard.ts — catch 블록이 handleApiError plain object의 message 필드를 직접 읽도록 수정 (기존: instanceof Error fallback으로 generic 메시지만 표시됨)
Key facts:
  - 원인: calcBlobFeeCap 하드코딩 2×, suggestGasPriceCaps→finishBlobTx 사이 stale cap
  - 해결: BlobFeeCapMultiplier(4×) + MaxBlobBaseFee(50 gwei) 임계값 플래그 추가
  - retry.Unrecoverable로 ErrBlobBaseFeeTooHigh 발생 시 30회 retry 없이 즉시 재큐
  - tokamak-thanos commit 8e67bbce, trh-sdk commit 13e1465
  - OP_BATCHER_DATA_AVAILABILITY_TYPE=calldata 임시 우회 해제됨
Key additions: DRB umbrella page — shared protocol flow (8 success + 23 failure paths), round state machine (IN_PROGRESS 6-branch HALTED), operator lifecycle (32 max, X8 slash accounting, notInProcess gate), dispute/slashing matrix, L2 gas model (CommitReveal2L2 + OVM oracle), ABI sync workflow (수동 복사 + abigen), environment matrix (Sepolia/OpSepolia/ThanosSepolia), integration test harness reference (128KB docker_nodes_quick_test.go, failure/stress/perf suites).

## [2026-04-15] fix | 로컬 L2 재배포 불가 버그 수정 (DB↔Docker 상태 불일치)
Repos: trh-backend (e70ebec, 8065a0f), trh-sdk (6077386)
Pages updated: [[tech-debt-and-risks]] — Known Bugs 섹션에 해결 기록

Root cause 1: `checkNoActiveLocalStack()` DB만 확인 → 컨테이너 없어도 409 반환
Root cause 2: `destroyLocalNetwork()` compose 파일 없을 때 nil 반환 → 볼륨 고아 상태

Fix A (trh-backend): `docker ps --filter label=com.docker.compose.project=<uuid>` 조회 추가.
  컨테이너 없으면 DB 자동 Terminated 보정 → 새 배포 허용.
Fix C (trh-sdk): compose 파일 없을 때 `docker volume rm -f trh-local-config trh-local-monitoring <uuid>_op-geth-data` 직접 실행.

## [2026-04-15] update | CrossTrade dApp 버그 픽스 3종 — defi-eth 프리셋 환경
Sources: trh-sdk commits 8af71e6, trh-backend commit e13669c, crossTrade commit 1103393

Pages updated:
  [[cross-trade]] — dApp 환경변수 포맷 변경, Thanos Sepolia destination_chains 설계 결정,
                    destination picker 버그 픽스, defi-eth native token 메타데이터 버그 픽스 섹션 추가

Key facts captured (비자명한 것만):
  - OKX 등 지갑은 서명 팝업 전 eth_estimateGas로 사전 시뮬레이션 → 컨트랙트 revert시 팝업 자체를 차단 ("서명이 안된다" 증상)
  - Thanos Sepolia L2toL2CTProxy(0x7BbEC...) 에는 우리가 배포한 신규 L2 chain ID가 미등록 → Thanos→신규L2 방향 시뮬레이션 revert
  - 해결: thanosL2L2Tokens destination_chains: [] → UI가 해당 경로를 애초에 차단
  - NEXT_PUBLIC_CHAIN_CONFIG (구버전) → NEXT_PUBLIC_CHAIN_CONFIG_L2_L1 + NEXT_PUBLIC_CHAIN_CONFIG_L2_L2 로 분리. trh-sdk local-compose.yml.tmpl도 동기화 (이전에 env var 이름 불일치로 L2_L2 config가 dApp에 전달되지 않았음)
  - L2_L2 토큰 포맷: [{name, address, destination_chains}] 배열. L2_L1 토큰 포맷: {ETH: addr, USDC: addr} flat map — 두 포맷이 다름
  - defi-eth 프리셋: L2NativeTokenName/Symbol을 "Ethereum"/"ETH"로 분기. 미전달시 지갑에 체인 추가할 때 "TON"으로 잘못 표시됨
  - 반대 방향(신규L2 → Thanos Sepolia)은 정상 — 신규L2 proxy에는 우리가 admin, Thanos chain ID 등록 완료

## [2026-04-16] fix | op-batcher blob fee 에러 재발 — suggestGasPriceCaps hack 제거
Repo: tokamak-thanos commit d8202223
Pages updated: [[op-batcher-blob-fee-spike]] — 재발 원인 + 2차 수정 히스토리 추가

Root cause: `8e67bbce`의 MaxBlobBaseFee 임계값 체크가 `2a9e294c`의 `CalcBlobFeeCancun(0)` hack과 충돌.
  suggestGasPriceCaps가 1 wei를 반환 → 임계값 체크 항상 통과 → EstimateGas에 BlobGasFeeCap=1 wei 전달
  → Sepolia 실제 fee > 1 wei → "max fee per blob gas less than block blob gas fee" 재발

Fix: suggestGasPriceCaps에서 CalcBlobFeeCancun(0) 제거, 실제 *head.ExcessBlobGas 복원.
  이제 Sepolia 비정상 excessBlobGas → blobBaseFee >> 50 gwei → ErrBlobBaseFeeTooHigh 발동 → EstimateGas 건너뜀.

## [2026-04-15] update | trh-platform DeploymentWatcher — 배포 실패 원인 표시
Pages updated: [[trh-platform]]

Changes:
  - 핵심 역할에 "Deployment watcher" 추가 (6번)
  - 주요 모듈에 DeploymentWatcher + NotificationStore 링크 추가
  - DeploymentWatcher 섹션 신설: 감지 전환 테이블, 실패 원인 추출 흐름, AppNotification 인터페이스, 주의사항

Key facts captured:
  - `FailedToDeploy`/`FailedToUpdate` 감지 시 `/api/v1/stacks/thanos/:stackId/deployments?limit=1` → logs?limit=50 순차 호출
  - 로그 포맷: JSON Lines. 추출 우선순위: 마지막 level==="error" message → 마지막 raw 줄 → undefined
  - 로그 조회 실패 시에도 notification은 반드시 발송 (fetchFailureReason 전체 try-catch → undefined)
  - AppNotification 인터페이스에 `detail?: string` 추가 (main + renderer 양쪽)
  - URL 패턴: `/api/v1/stacks/thanos/{stackId}/...` — "thanos" 세그먼트 필수
  - NotificationPage.tsx: `detail` 있으면 알림 카드에 모노스페이스 빨간 텍스트로 인라인 표시

## [2026-04-16] ingest | thanos-deployer deployment logic analysis (final)
Sources: Complete code-level analysis from 45 files across 3 repos (tokamak-thanos, trh-sdk, trh-backend)

Page created:
  [[thanos-deployer-analysis]] — Executive summary with key findings, 8-layer architecture, 6-phase flow

Analysis documents added to tokamak-thanos/docs/analysis/:
  PHASE_2_ANALYSIS.md (37.4KB) — Web UI request → HTTP POST → trh-backend handler
  PHASE_3_ANALYSIS.md (57.2KB) — Backend queuing, TaskManager goroutine orchestration
  PHASE_4_ANALYSIS.md (55.9KB) — L1 contract deployment via Foundry (35+ contracts, 4 phases)
  PHASE_5_ANALYSIS.md (70.1KB) — L2 Genesis generation (op-chain-ops, 14+ steps, 40+ predeploys)
  PHASE_6_ANALYSIS.md (46.6KB) — Result persistence, StackMetadata updates, client notification
  code-reference-table.md (26.6KB) — 51 functions mapped across 45 files
  thanos-deployer-flow-analysis.md (48.9KB) — Main document with 6 appendices

Key facts captured (6 phases):
  - Phase 1: Electron SSO auth (AWS SigV4 token exchange)
  - Phase 2: Next.js embedded UI → POST /api/v1/stacks/thanos with DeployThanosRequest JSON
  - Phase 3: Go TaskManager enqueues → goroutine loop → sequential phase execution
  - Phase 4: trh-sdk calls start-deploy.sh (Foundry forge script) → deploy.json with 35+ contract addresses
  - Phase 5: op-chain-ops NewL2Genesis() reads deploy.json → bytecode patching → genesis.json/rollup.json
  - Phase 6: UpdateStackMetadata() writes to DB → webhook notification → UI notification

Critical pitfalls documented:
  1. Blob fee spike (excessBlobGas edge case) — tokamak-thanos commit d8202223 fix
  2. Bytecode patching (hardcoded offsets per Openzeppelin version)
  3. Environment validation (missing .env checks → zero contract addresses)
  4. Cross-Trade scope isolation (local-only vs L2-L2 cross-chain)
  5. Hard fork compatibility (Ecotone/Fjord/Granite mismatch)

Risk analysis: 3 high, 3 medium, 2 low risks with mitigation strategies.
Call depth: 8+ synchronous calls from HTTP handler to op-chain-ops.
Data transformations: JSON → .env → deploy.json → op-chain-ops → genesis.json (3 steps).
State mutations: 6 major transforms, 14+ predeploy bytecode operations.

Analysis scope: Electron → trh-backend → trh-sdk → Foundry → op-chain-ops → StackMetadata → Client.
Not covered: AWS infrastructure, Solidity implementation details, local Docker deployment.

Verification checklist included (8 grep commands for validation).
Cross-references: blob fee fixes (tokamak-thanos commits), ec2-deploy, preset-system, design-decisions.
