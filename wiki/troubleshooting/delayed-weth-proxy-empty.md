---
updated: 2026-04-28
component: tokamak-deployer / trh-sdk / tokamak-thanos
---

# delayedWETHProxyAddr is empty

## Symptom

`initDisputeGameFactory` 실행 시 다음 오류로 실패:

```
failed to initialize DisputeGameFactory: initDisputeGameFactory: delayedWETHProxyAddr is empty
```

DRB / fault-proof 프리셋 배포 시 DisputeGameFactory 초기화 단계에서 발생.

## Root Cause

`tokamak-deployer v0.0.6`의 fault-proof 블록(steps 27-32)이 `DisputeGameFactory`와 `AnchorStateRegistry`만 배포했으며 **`DelayedWETH`를 배포하지 않았다**.

`trh-sdk/pkg/stacks/thanos/local_network.go`의 `initDisputeGameFactory`는 `deployedContracts.DelayedWETHProxy`를 필수 파라미터로 전달하는데, deployer가 이 주소를 `deploy-output.json`에 기록하지 않아 빈 문자열이 전달되었다.

## Fix

### tokamak-deployer v0.0.7 (commit `2360cb483f`)

`DelayedWETH` 배포 3단계(steps 33-35)를 fault-proof 블록에 추가:

| Step | 동작 |
|------|------|
| 33 | `DelayedWETHProxy` deploy (Proxy with ProxyAdmin) |
| 34 | `DelayedWETH` impl deploy (constructor: `_delay uint256`) |
| 35 | `DelayedWETHProxy` → impl upgrade |

변경 파일:
- `cmd/deploy-artifacts/DelayedWETH.json` 추가 (forge-artifacts에서 ABI + bytecode 추출)
- `internal/deployer/types.go`: `DeployOutput.DelayedWETHProxy`, `DeployConfig.DelayedWETHDelay` 추가
- `internal/deployer/contracts.go`: `faultProofSteps: 6 → 9`
- `cmd/deploy_contracts.go`: `--delayed-weth-delay` 플래그 추가 (기본값 0)

### trh-sdk v? (commit `e2c1ddf`)

- `TokamakDeployerVersion: "v0.0.6" → "v0.0.7"`
- `deployContractsOpts.DelayedWETHDelay uint64` 필드 추가
- `buildDeployContractsArgs`: `DelayedWETHDelay > 0` 시 `--delayed-weth-delay` 플래그 emit

## Notes

- `initialize(address _owner, address _config)` 호출 **불필요**: 로컬 테스트넷에서 `hold()`(owner-only 복구 함수)는 정상 게임 lifecycle에서 호출되지 않음. `unlock()` → `withdraw()` 흐름은 owner 없이 동작.
- `DelayedWETHDelay=0`은 로컬 테스트넷에 적합 (인출 지연 없음).
- 신규 배포는 `v0.0.7` 이미지 사용 시 workaround 없이 정상 동작.
