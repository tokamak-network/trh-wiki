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
  [[aws-sso]], [[docker-compose-lifecycle]], [[ec2-deploy]], [[release]],
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
