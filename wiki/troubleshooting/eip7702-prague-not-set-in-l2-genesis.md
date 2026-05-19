---
updated: 2026-05-12
---

# EIP-7702 type 4 tx "pool not yet in Prague" — L2 genesis PragueTime 누락

## 증상

AA Paymaster setup 중 EIP-7702 delegation tx 전송 실패:

```
Failed to set up AA Paymaster
{"err": "failed to send EIP-7702 delegation tx: transaction type not supported: type 4 rejected, pool not yet in Prague"}
```

Isthmus(`l2GenesisIsthmusTimeOffset: "0x0"`)가 활성화된 L2에서도 발생.

## 근본 원인

`tokamak-thanos/op-chain-ops/genesis/genesis.go` `NewL2Genesis()`가 OP Stack 프로토콜 포크를 EVM 실행 포크에 매핑할 때 Isthmus→Prague 매핑을 누락했다.

### OP Stack ↔ EVM 포크 매핑 패턴

| OP Stack 포크 | EVM 실행 포크 | genesis.go 매핑 |
|---|---|---|
| Canyon | Shanghai | `ShanghaiTime = CanyonTime` ✓ |
| Ecotone | Cancun | `CancunTime = EcotoneTime` ✓ |
| **Isthmus** | **Prague** | **수정 전: 누락 / 수정 후: 추가** |

op-geth의 txpool은 EIP-7702(type 4, SetCode) tx를 받으면 `ChainConfig.PragueTime`을 확인한다 (`txpool/validation.go:105`). `PragueTime = nil`이면 "pool not yet in Prague" 에러로 거부한다.

`l2GenesisIsthmusTimeOffset`이 설정되어 `IsthmusTime`이 genesis에 포함되더라도, `PragueTime`은 별개 필드이므로 자동으로 설정되지 않는다.

### 에러 전파 경로

1. deploy-config에 `l2GenesisIsthmusTimeOffset: "0x0"` → `IsthmusTime = 0` 설정
2. `NewL2Genesis()`가 `PragueTime` 없이 genesis 생성 → `ChainConfig.PragueTime = nil`
3. op-geth txpool: `IsPrague()` → `isTimestampForked(nil, head.Time)` → `false`
4. SetCode tx(type 4) 거부

## 수정

`tokamak-thanos/op-chain-ops/genesis/genesis.go` `NewL2Genesis()` 내에 추가:

```go
IsthmusTime: config.IsthmusTime(block.Time()),
PragueTime:  config.IsthmusTime(block.Time()), // ← 추가
```

커밋: `tokamak-thanos 0e66bf4`

## 참고

- 에러 검증 위치: `tokamak-thanos-geth/core/txpool/validation.go:105`
- `IsPrague()` 구현: `tokamak-thanos-geth/params/config.go:743`
- AA Paymaster EIP-7702 delegation 코드: `trh-sdk/pkg/stacks/thanos/aa_setup.go:241`
