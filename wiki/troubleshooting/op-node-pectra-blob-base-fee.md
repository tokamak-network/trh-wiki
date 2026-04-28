---
updated: 2026-04-27
component: tokamak-thanos / op-node / trh-sdk
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

`tokamak-thanos/op-node/rollup/derive/l1_block_info.go:501`이 항상 `eth.CalcBlobFeeCancun(*ebg)`를 호출했다.

### 왜 잘못된가

`CalcBlobFeeCancun(excessBlobGas)`는 **Cancun UpdateFraction=3338477**을 고정으로 사용한다:

```go
// op-service/eth/block_info.go (buggy path)
func CalcBlobFeeCancun(excessBlobGas uint64) *big.Int {
    // 더미 헤더 생성 → RequestsHash = nil → PragueTime 미설정 → Cancun UpdateFraction
    return eth.CalcBlobFeeDefault(dummyHeader)
}
```

Sepolia는 2025년 3월 Pectra(Prague)를 활성화했고, 이후 `excessBlobGas`가 약 193M까지 상승했다:

| 공식 | UpdateFraction | excessBlobGas=193M 결과 |
|------|---------------|------------------------|
| Cancun | 3,338,477 | ~10^25 wei (잘못됨) |
| Prague | 5,007,716 | ~수 gwei (정상) |

Cancun 공식으로 193M excessBlobGas를 계산하면 지수 함수 특성상 ~10^25 wei가 나온다.
이 값이 L1 Info deposit 트랜잭션에 `BlobBaseFee`로 기록되면 L2 GasPrice 계산이 깨진다.

### PectraBlobScheduleTime은 왜 효과 없었나

`rollup.json`에 `PectraBlobScheduleTime`을 설정하면 op-node 시작 오류(`ErrMissingPectraBlobSchedule`)는 억제되지만, 버그 버전에서는 override 경로도 동일하게 `eth.CalcBlobFeeCancun`을 호출하는 no-op이었다:

```go
// 버그 버전 (수정 전)
if isEcotoneActivated {
    if ebg := block.ExcessBlobGas(); ebg != nil {
        l1BlockInfo.BlobBaseFee = eth.CalcBlobFeeCancun(*ebg)  // 항상 Cancun
    }
    // PectraBlobScheduleTime override도 동일 공식 → no-op
    if t := rollupCfg.PectraBlobScheduleTime; t != nil && block.Time() < *t {
        l1BlockInfo.BlobBaseFee = eth.CalcBlobFeeCancun(*ebg)  // 동일
    }
}
```

## Fix

**tokamak-thanos commit `07c68f913a`**: `block.BlobBaseFee()` 사용으로 교체.

```go
// 수정 후
if isEcotoneActivated {
    // CalcBlobFeeDefault: 실제 L1 헤더의 RequestsHash 확인
    // post-Pectra 블록(RequestsHash != nil) → Prague UpdateFraction=5007716 선택
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

`block.BlobBaseFee()` → `CalcBlobFeeDefault(header)`:
- `header.RequestsHash != nil` (post-Pectra L1 블록) → dummyChainCfg에 `PragueTime=0` 설정 → Prague UpdateFraction=5007716
- `header.RequestsHash == nil` (pre-Pectra L1 블록) → Cancun UpdateFraction=3338477

**업스트림 확인**: `ethereum-optimism/optimism` develop 브랜치는 `block.BlobBaseFee(l1ChainConfig)` (ChainConfig 파라미터 포함)를 사용. tokamak-thanos 인터페이스는 파라미터 없는 버전이라 `block.BlobBaseFee()`가 동등한 backport.

## 임시 L1 Workaround (적용됨)

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
- op-node가 다음 Sepolia L1 블록을 처리할 때 (SystemConfig 이벤트 포함 블록 이후) 효과 발동

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
- op-node 이미지 재빌드 필요: `07c68f913a` 커밋 포함된 이미지로 갱신 후 로컬 체인 재시작
