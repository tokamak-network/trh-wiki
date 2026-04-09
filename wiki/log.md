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
