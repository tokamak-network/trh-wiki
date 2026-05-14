---
title: L1StandardBridgeProxy 미초기화 — 로컬 배포 시 bridgeETH revert
created: 2026-05-14
type: troubleshooting
---

# L1StandardBridgeProxy 미초기화 — 로컬 배포 시 bridgeETH revert

## 증상

op-bridge에서 ETH Deposit 버튼 클릭 시:

```
Error: cannot estimate gas; transaction may fail or may require manual gas limit
reason="execution reverted"
to: 0xa79669db00CeBDbd6Ff33Be82C7EE2ff539745E9 (L1StandardBridgeProxy)
value: 0x038d7ea4c68000 (0.001 ETH)
data: 0x162f1686... (bridgeETH call)
```

`bridgeETH(uint256,uint32,bytes)` 가스 추정 단계에서 revert. Deposit 자체가 불가능.

## 근본 원인

`tokamak-deployer`는 프록시 컨트랙트에 대해 `upgrade(proxy, impl)`만 호출하고 `initialize()`는 호출하지 않는다.

결과:
- `L1StandardBridgeProxy.MESSENGER()` → `0x0000000000000000000000000000000000000000`
- `bridgeETH()` 내부에서 `messenger.sendMessage()` 호출 → address(0) 호출 → revert

**AWS 배포 경로**(`deploy_chain.go`)는 `initL1StandardBridge()`를 호출하고 있었지만, **로컬 배포 경로**(`local_network.go`)에서는 누락되어 있었다.

진단 방법:
```bash
cast call <L1StandardBridgeProxy> 'MESSENGER()(address)' --rpc-url <L1_RPC>
# 0x0000000000000000000000000000000000000000 → 미초기화
```

## Thanos L1StandardBridge initialize() 시그니처

```
initialize(address _messenger, address _superchainConfig, address _systemConfig)
selector: c0c53b8b
```

표준 OP Stack(`initialize(address,address)`)과 달리 파라미터가 3개 (SystemConfig 추가).

## 영구 수정 (trh-sdk)

`trh-sdk/pkg/stacks/thanos/local_network.go`에 `initL1StandardBridge` 호출 추가:

```go
// CDM 초기화 이후, OptimismPortal 초기화 이전에 삽입
logStep("Initializing L1StandardBridge")
bridgeErr := initL1StandardBridge(
    ctx, t.logger, t.deployConfig.L1RPCURL, t.deployConfig.AdminPrivateKey,
    deployedContracts.L1StandardBridgeProxy,
    deployedContracts.L1CrossDomainMessengerProxy,
    deployedContracts.SuperchainConfigProxy,
    deployedContracts.SystemConfigProxy,
    t.deployConfig.L1ChainID,
)
```

**수정 커밋**: `0fe9569` (main)

`initL1StandardBridge`는 idempotent: `MESSENGER()`가 이미 non-zero이면 skip.

## 기존 배포에 대한 핫픽스

이미 생성된 배포(MESSENGER() = 0x0)는 다음 명령으로 직접 초기화:

```bash
L1_RPC="<L1_RPC_URL>"
ADMIN_KEY="<admin_private_key>"  # settings.json의 admin_private_key
BRIDGE_PROXY="<L1StandardBridgeProxy>"
CDM_PROXY="<L1CrossDomainMessengerProxy>"
SUPERCHAIN_CONFIG="<SuperchainConfigProxy>"
SYSTEM_CONFIG="<SystemConfigProxy>"

# 시뮬레이션 먼저 (가스 추정 성공 = 초기화 가능)
cast estimate $BRIDGE_PROXY \
  "initialize(address,address,address)()" \
  $CDM_PROXY $SUPERCHAIN_CONFIG $SYSTEM_CONFIG \
  --rpc-url $L1_RPC \
  --from $(cast wallet address $ADMIN_KEY)

# 실제 전송
cast send $BRIDGE_PROXY \
  "initialize(address,address,address)()" \
  $CDM_PROXY $SUPERCHAIN_CONFIG $SYSTEM_CONFIG \
  --private-key $ADMIN_KEY \
  --rpc-url $L1_RPC \
  --gas-limit 300000 \
  --gas-price 5gwei \
  --priority-gas-price 2gwei

# 검증
cast call $BRIDGE_PROXY 'MESSENGER()(address)' --rpc-url $L1_RPC
# CDM 주소 반환되면 성공
```

주소는 `settings.json`과 `deploy-output.json`에서 확인.

## 주의

- Thanos L1StandardBridge는 `MESSENGER()` (대문자)를 사용. 표준 OP는 `messenger()`.
- `L1UsdcBridge` 초기화와는 별개 문제. 두 버그가 동시에 발생 가능.
- `initL1StandardBridge`는 initialize 전에 pre-flight `CallContract`로 시뮬레이션 실행 — revert 시 트랜잭션 전송 없이 에러 반환.
