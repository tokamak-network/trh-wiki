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
