---

updated: 2026-05-19
sources: []
related: []
tags: [troubleshooting]
---
# local+Testnet 배포 시 deploy-l1-contracts 스텝 누락

**레포**: trh-backend  
**수정 커밋**: 351cebb  
**파일**: `pkg/services/thanos/helpers.go`

## 증상

`general` (또는 기타) preset으로 `InfraProvider=local`, `Network=Testnet` 배포 시:
- DB에 `deploy-local-infra` 레코드만 생성됨 (`deploy-l1-contracts` 없음)
- `deploy-local-infra` 즉시 실패: `"contracts are not deployed successfully; run deploy-contracts first"`
- `settings.json`의 `deploy_contract_state: null`

## 근본 원인

`getThanosStackDeployments` (`helpers.go:39`)의 조건이 잘못되어 있었음:

```go
// 버그: local provider 전체에서 L1 contracts 스텝 건너뜀
if !deployedContracts && config.InfraProvider != "local" {
```

이 조건은 `local` infra provider에 두 가지 케이스가 있음을 구분하지 못함:

| 케이스 | Network | 올바른 동작 |
|--------|---------|------------|
| LocalDevnet | `LocalDevnet` | SDK.Deploy()가 L1+L2 함께 처리 → L1 contracts 스텝 불필요 |
| Local + Sepolia | `Testnet` | Sepolia에 컨트랙트 먼저 배포 → L1 contracts 스텝 **필수** |
| Local + Mainnet | `Mainnet` | Mainnet에 컨트랙트 먼저 배포 → L1 contracts 스텝 **필수** |

## 수정

```go
// 수정: LocalDevnet 네트워크일 때만 건너뜀 (SDK가 L1+L2 함께 처리)
if !deployedContracts && config.Network != entities.DeploymentNetworkLocalDevnet {
```

## 부수 수정

`deployment_test.go`의 `TestInstallDRBOperatorsCallOrder` 컴파일 타임 체크 제거.  
`installDRBOperators` 메서드가 `31c2295`(refactor)에서 삭제됐는데 테스트만 남아 있던 상태.

## 확인 방법

배포 후 DB에서:
```sql
SELECT step, status FROM deployments WHERE stack_id = '<id>' ORDER BY created_at;
```
`deploy-l1-contracts` (Pending) → `deploy-local-infra` (Pending) 두 레코드가 모두 있어야 함.
