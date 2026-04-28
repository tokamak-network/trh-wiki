---
updated: 2026-04-28
component: tokamak-thanos / op-node / op-service
---

# op-node Pectra BlobBaseFee 계산 오류

## Symptom

op-batcher와 op-proposer가 calldata 모드로 전환했음에도 drb-regular(DRB 오퍼레이터) 트랜잭션이 계속 실패:

```
insufficient funds for gas * price + value
```

또는 op-node 로그에서 L1 Info deposit 트랜잭션의 blobBaseFee 필드가 비정상적으로 큼:

```
blobBaseFee=10000000000000000000000000  # ~10^25 wei (정상은 ~1-10 gwei)
```

## Root Cause

### 진짜 근본 원인: `op-service/sources/types.go`

`headerInfo.BlobBaseFee()` (commit `2f1b7245ee` 이전) 가 `eth.CalcBlobFeeCancun(excessBlobGas)` 를 직접 호출:

```go
// op-service/sources/types.go — 수정 전 버그
func (h headerInfo) BlobBaseFee() *big.Int {
    if h.Header.ExcessBlobGas == nil {
        return nil
    }
    return eth.CalcBlobFeeCancun(*h.Header.ExcessBlobGas)  // Cancun 고정 → 버그
}
```

`headerInfo`는 `EthClient.InfoByHash()` / `FetchReceipts()` → `RPCHeader.Info()` 경로에서 반환되는 concrete type이다.
`l1_block_info.go`의 `block.BlobBaseFee()` 호출은 `eth.BlockInfo` 인터페이스를 통해 dispatch되므로,
실제로는 이 `headerInfo.BlobBaseFee()` 메서드가 실행된다.

### 왜 이전 수정(07c68f913a)은 부족했나

`07c68f913a` 커밋은 `op-node/rollup/derive/l1_block_info.go` 에서 call site를 `eth.CalcBlobFeeCancun` → `block.BlobBaseFee()` 로 변경했다. 그러나 `block` 의 concrete type인 `headerInfo` (sources/types.go)의 `BlobBaseFee()` 구현 자체는 여전히 `CalcBlobFeeCancun` 을 사용했으므로 실질적인 변화가 없었다.

`eth.BlockInfo` 인터페이스를 구현하는 타입이 두 가지:
- `*headerBlockInfo` (`eth/block_info.go`) — `CalcBlobFeeDefault` 사용 → 정상
- `*headerInfo` (`sources/types.go`) — `CalcBlobFeeCancun` 사용 → **L1 fetcher가 실제 반환하는 타입**

### 왜 문제가 되는가

`CalcBlobFeeCancun(excessBlobGas)`는 **Cancun UpdateFraction=3338477**을 고정으로 사용한다:

| 공식 | UpdateFraction | excessBlobGas=193M 결과 |
|------|---------------|------------------------|
| Cancun | 3,338,477 | ~10^25 wei (잘못됨) |
| Prague | 5,007,716 | ~수 gwei (정상) |

Sepolia는 2025년 3월 Pectra(Prague)를 활성화했고, 이후 `excessBlobGas`가 약 188-194M까지 상승했다.
Cancun 공식으로 이 값을 계산하면 지수 함수 특성상 ~10^24~25 wei가 나온다.
이 값이 L1 Info deposit 트랜잭션에 `BlobBaseFee`로 기록되면 L2 GasPrice 계산이 깨진다.

### `RequestsHash` 필드

`RPCHeader` (sources/types.go)는 Alchemy/RPC 응답에서 `requestsHash`를 올바르게 파싱한다:

```go
func (hdr *RPCHeader) createGethHeader() *types.Header {
    return &types.Header{
        // ...
        RequestsHash: hdr.RequestsHash,  // post-Pectra L1 블록에서 non-nil
    }
}
```

따라서 `headerInfo.Header.RequestsHash`는 이미 올바르게 설정되어 있었다 — `BlobBaseFee()` 메서드만 이를 활용하지 않았을 뿐.

## Fix

### 실제 수정: commit `2f1b7245ee` (`op-service/sources/types.go`)

```go
// 수정 후
func (h headerInfo) BlobBaseFee() *big.Int {
    if h.Header.ExcessBlobGas == nil {
        return nil
    }
    return eth.CalcBlobFeeDefault(h.Header)  // RequestsHash 확인 → Prague 공식 선택
}
```

`CalcBlobFeeDefault(header)`:
- `header.RequestsHash != nil` (post-Pectra L1 블록) → `PragueTime=0` 설정 → UpdateFraction=5007716
- `header.RequestsHash == nil` (pre-Pectra L1 블록) → Cancun UpdateFraction=3338477

### 참고: 이전 수정 (call site, commit `07c68f913a`, `op-node/rollup/derive/l1_block_info.go`)

```go
// 수정 후
if isEcotoneActivated {
    l1BlockInfo.BlobBaseFee = block.BlobBaseFee()

    // 과거 호환: PectraBlobScheduleTime 이전 블록은 Cancun 공식 강제
    if t := rollupCfg.PectraBlobScheduleTime; t != nil && block.Time() < *t {
        if ebg := block.ExcessBlobGas(); ebg != nil {
            l1BlockInfo.BlobBaseFee = eth.CalcBlobFeeCancun(*ebg)
        } else {
            l1BlockInfo.BlobBaseFee = nil
        }
    }
}
```

이 수정은 call site를 올바르게 변경했으나, dispatch target (`headerInfo.BlobBaseFee`) 수정 없이는 효과가 없었다.

**업스트림 확인**: `ethereum-optimism/optimism` develop 브랜치는 `block.BlobBaseFee(l1ChainConfig)` (ChainConfig 파라미터 포함)를 사용. tokamak-thanos 인터페이스는 파라미터 없는 버전이라 `CalcBlobFeeDefault(h.Header)` 가 동등한 backport.

## 임시 L1 Workaround (적용됨, 신규 배포 시 불필요)

op-node 이미지 재빌드 전 drb-regular 트랜잭션이 통과하도록 SystemConfig의 blobBaseFeeScalar를 0으로 설정:

```bash
# cast send — setGasConfigEcotone(baseFeeScalar=1368, blobBaseFeeScalar=0)
cast send <SYSTEM_CONFIG_PROXY> \
  "setGasConfigEcotone(uint32,uint32)" 1368 0 \
  --rpc-url $L1_RPC \
  --private-key $DEPLOYER_PRIVATE_KEY
```

- `blobBaseFeeScalar=0` → L2 트랜잭션 gas 계산에서 blob fee 항 = 0 → 비정상 blobBaseFee 영향 없음
- 이 설정은 L1 스토리지에 저장되어 Docker 재시작 후에도 유지
- **신규 배포(볼륨 삭제 후 재배포)에서는 이 workaround 없이도 정상 동작** (이미지에 `2f1b7245ee` 포함 시)

### 적용 기록

| 날짜 | 대상 체인 | SystemConfig Proxy | TX | Sepolia Block |
|------|---------|-------------------|-----|---------------|
| 2026-04-27 | DRB gaming preset (uuid `fd621bd4`) | `0x0b8429525C3C39b5060b9c7b616f7406B099Ad55` | `0x937b838d...` | 10743056 |
| 2026-04-28 | DRB gaming preset (uuid `fd621bd4`, 재배포 후) | `0x0b8429525C3C39b5060b9c7b616f7406B099Ad55` | `0x305fd43d879eb4037e945e3328115eeecccc7f0b2921a6f58af362caa037216d` | 10746610 |
| 2026-04-28 | Full preset (uuid `7510de41`) | `0x3c434c816c8b555825f54e6ff98d8d5ffcfe2533` | `0xc13c3502fd284ba5aa716b8bf4f40671db56f1caa374b06d2d7553f81b86b3a9` | 10747603 |

## Impact

이 버그는 `l1_block_info.go`에서 `L1InfoDeposit` 트랜잭션 bytes를 결정한다.
post-Pectra L1 블록을 처리하는 기존 로컬 체인은 **chain wipe** 후 재배포가 필요하다.

## 재발 방지

- `PectraBlobScheduleTime`을 Sepolia Pectra 활성화 시점으로 설정해도 이 버그는 우회되지 않음
- 근본 수정은 `op-service/sources/types.go` commit `2f1b7245ee` 에 포함
- 신규 배포는 해당 커밋이 포함된 `tokamaknetwork/thanos-op-node:nightly` 이미지 사용 시 workaround 불필요
