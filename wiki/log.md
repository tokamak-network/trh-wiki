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
  [[cross-trade]], [[deposit-tx]], [[aws-sso]], [[docker-compose-lifecycle]],
  [[ec2-deploy]], [[release]], [[abigen-vs-manual-calldata]],
  [[deposit-tx-vs-genesis-predeploy]], [[separate-compose-for-crosstrade]],
  [[docker-health-checks]], [[l2-deposit-verification]]
