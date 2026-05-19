---
updated: 2026-04-27
component: tokamak-thanos / op-proposer / trh-sdk
sources: []
related:
  - "[[tokamak-deployer-logging]]"
tags: [troubleshooting]
---


# L2OutputOracle Uninitialized — op-proposer "only the proposer address can propose new outputs"

## Symptom

op-proposer 컨테이너 로그:

```
err="only the proposer address can propose new outputs"
```

또는 `proposeL2Output()` 호출 자체가 revert됨. L2 safe head가 진행되지 않음.

## Root Cause

tokamak-deployer의 L2OutputOracle 배포 단계(Steps 24-26)에서 proxy → implementation → upgrade 순으로
컨트랙트를 배포하지만, `initialize()` 를 호출하지 않는다.

결과:
- `L2OutputOracle.proposer()` = `address(0)`
- `proposeL2Output()` 내부에서 `msg.sender != proposer` 체크 → revert

이 문제는 `initL1CrossDomainMessenger()` 에서 해결한 것과 동일한 패턴이다.

## Fix — trh-sdk commit `ce4ce65` (Apr 27)

`deploy_chain.go`에 `initL2OutputOracle()` 추가, `local_network.go`의 `StartLocalNetwork()` 에서 CDM init 직후 호출.

### 초기화 파라미터

| 파라미터 | 소스 |
|---------|------|
| `submissionInterval` | `deploy-config.json` → `L2OutputOracleSubmissionInterval` |
| `l2BlockTime` | `deployConfig.ChainConfiguration.L2BlockTime` |
| `startingBlockNumber` | `deploy-config.json` → `L2OutputOracleStartingBlockNumber` |
| `startingTimestamp` | `deploy-config.json` → `L2OutputOracleStartingTimestamp` |
| `proposer` | `deploy-config.json` → `L2OutputOracleProposer` |
| `challenger` | `deploy-config.json` → `L2OutputOracleChallenger` |
| `finalizationPeriodSeconds` | `deployConfig.ChainConfiguration.GetFinalizationPeriodSeconds()` |

### Idempotency

초기화 전 `proposer()` 셀렉터로 현재 값을 조회해 non-zero이면 skip:

```go
// 4-byte selector: keccak256("proposer()")
proposerSelector := crypto.Keccak256([]byte("proposer()"))[:4]
result, err := l1Client.CallContract(ctx, ethereum.CallMsg{
    To:   &proxyAddr,
    Data: proposerSelector,
}, nil)
if err == nil && len(result) >= 32 {
    addr := common.BytesToAddress(result[12:32])
    if addr != (common.Address{}) {
        logger.Infow("L2OutputOracle already initialized, skipping", "proposer", addr.Hex())
        return nil
    }
}
```

### ABI Encoding (수동)

```
selector (4 bytes) + 7 × 32 bytes
  [0]  submissionInterval   — uint256, FillBytes()
  [1]  l2BlockTime          — uint256, FillBytes()
  [2]  startingBlockNumber  — uint256, FillBytes()
  [3]  startingTimestamp    — uint256, FillBytes()
  [4]  proposer             — address, right-aligned at offset +12
  [5]  challenger           — address, right-aligned at offset +12
  [6]  finalizationPeriodSeconds — uint256, FillBytes()
```

## L2OutputOracle.initialize() 서명

```solidity
function initialize(
    uint256 _submissionInterval,
    uint256 _l2BlockTime,
    uint256 _startingBlockNumber,
    uint256 _startingTimestamp,
    address _proposer,
    address _challenger,
    uint256 _finalizationPeriodSeconds
) external
```

## 관련 파일

- `trh-sdk/pkg/stacks/thanos/deploy_chain.go` — `initL2OutputOracle()` 구현
- `trh-sdk/pkg/stacks/thanos/local_network.go` — CDM init 블록 직후 호출 위치
- `trh-sdk/pkg/types/deploy_config_template.go` — `DeployConfigTemplate` (L2OO 파라미터 소스)

## 수동 수정 (긴급 시)

배포된 체인에서 이미 발생한 경우 `cast send` 로 수동 초기화:

```bash
cast send <L2OutputOracleProxy> \
  "initialize(uint256,uint256,uint256,uint256,address,address,uint256)" \
  300 2 0 <startingTimestamp> \
  <proposerAddr> <challengerAddr> 12 \
  --rpc-url <L1_RPC_URL> \
  --private-key <ADMIN_PRIVATE_KEY>
```

`startingTimestamp`는 deploy-config.json의 `l2OutputOracleStartingTimestamp` 값.

## Related

- [[tokamak-deployer-logging]] — 동일 "deployer가 initialize 미호출" 패턴
- 참고: `initL1CrossDomainMessenger()` in `deploy_chain.go` — 동일 패턴으로 CDM 초기화
