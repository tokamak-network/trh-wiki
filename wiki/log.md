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
