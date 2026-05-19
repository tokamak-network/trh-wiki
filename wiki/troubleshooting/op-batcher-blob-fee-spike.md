---
updated: 2026-04-27 (rev2)
component: tokamak-thanos / op-batcher / trh-sdk
sources: []
related: []
tags: [troubleshooting]
---


# op-batcher Blob Fee Spike Fix

## Symptom

```
err="failed to estimate gas: max fee per blob gas less than block blob gas fee"
```

op-batcher가 EIP-4844 blob tx 제출을 시도할 때 Sepolia L1의 blob base fee 스파이크 상황에서 위 오류로 실패한다.

## Root Cause

`op-service/txmgr/txmgr.go`의 `calcBlobFeeCap`이 `2 * blobBaseFee`로 고정되어 있고,
`craftTx` 내부에서 `suggestGasPriceCaps` → `EstimateGas` → `finishBlobTx` 사이에
blob base fee가 스파이크하면 이미 조회한 cap이 stale 상태가 되어 L1 blobpool에서 거부된다.

- 업스트림 PR optimism#11212 (`max-l1-blob-base-fee` 플래그)가 이 포크에 미백포트.
- `FeeLimitMultiplier` (5×) 설정도 stale cap 기준 상대값이라 무력.

## Fix History

### 1차 수정 — commit `8e67bbce` (Apr 15)

| 변경 | 파일 |
|------|------|
| `retry.Unrecoverable` 추가 — 30회 retry 없이 즉시 중단 | `op-service/retry/operation.go` |
| `BlobFeeCapMultiplier` / `MaxBlobBaseFee` CLI 플래그 추가 | `op-service/txmgr/cli.go` |
| `(m *SimpleTxManager).calcBlobFeeCap()` — 배수 설정화 (기본 4×) | `op-service/txmgr/txmgr.go` |
| `craftTx`: 임계값 선검사 + `finishBlobTx` 직전 blob base fee 재조회 | `op-service/txmgr/txmgr.go` |
| `ErrBlobBaseFeeTooHigh` sentinel + driver Warn 로그 | `op-batcher/batcher/driver.go` |

**재발 원인**: `8e67bbce` 이전 `2a9e294c` (Apr 14)에서 `suggestGasPriceCaps`를
`CalcBlobFeeCancun(0) = 1 wei` 반환으로 바꿨는데, `8e67bbce`가 이를 되돌리지 않아
두 커밋이 충돌했다:

- `suggestGasPriceCaps` → blobBaseFee = 1 wei
- 임계값 체크: `1 wei < MaxBlobBaseFee (50 gwei)` → 항상 통과 → `ErrBlobBaseFeeTooHigh` 미발동
- `EstimateGas`에 `BlobGasFeeCap = 1 wei` 전달 → Sepolia 실제 fee > 1 wei → 동일 에러 재발

### 2차 수정 — commit `d8202223` (Apr 16)

`suggestGasPriceCaps`에서 `CalcBlobFeeCancun(0)` hack 제거:

```go
// Before (2a9e294c hack — incompatible with 8e67bbce threshold check)
blobFee = eth.CalcBlobFeeCancun(0)

// After — real excessBlobGas makes threshold check meaningful
blobFee = eth.CalcBlobFeeCancun(*head.ExcessBlobGas)
```

이제 실제 `excessBlobGas`가 반환되므로:
- Sepolia의 비정상적 excessBlobGas → blobBaseFee >> 50 gwei
- 임계값 체크 발동 → `ErrBlobBaseFeeTooHigh` → EstimateGas 건너뜀
- 로그: `"Blob base fee above threshold, pausing submission"`

## Configuration

`op-batcher` 환경 변수:

```bash
OP_BATCHER_DATA_AVAILABILITY_TYPE=blobs           # calldata 우회 해제
OP_BATCHER_TXMGR_BLOB_FEE_CAP_MULTIPLIER=4        # 기본 4× (구 하드코딩 2×)
OP_BATCHER_TXMGR_MAX_L1_BLOB_BASE_FEE=0           # 0 = threshold 비활성화 (항상 제출)
```

trh-sdk `local-compose.yml.tmpl`에 자동 주입됨 (commit `13e1465`).

### 3차 수정 — trh-sdk commit `5e0301a` (Apr 27)

`MaxBlobBaseFeeGwei`를 `"50"` → `"0"` (비활성화)으로 변경:

Sepolia blob fee가 `4.4e25 wei` 수준의 극단적 스파이크 시 50 gwei 임계값이 초과되어
op-batcher가 무기한 paused 상태가 됨 → `safe_l2 = 0` (L1에 배치 미확인).

`OP_BATCHER_TXMGR_MAX_L1_BLOB_BASE_FEE=0`의 의미:
- `txmgr/cli.go:379`: `if cfg.MaxBlobBaseFeeGwei > 0 { maxBlobBaseFee = ... }` → 0이면 건너뜀
- `txmgr.go:265`: `m.cfg.MaxBlobBaseFee != nil` 체크 → nil이면 임계값 체크 자체 없음
- 결과: blob fee 크기와 무관하게 항상 제출

Sepolia 테스트넷은 blob fee가 실제 비용이 아니므로 uncapped 제출이 50 gwei threshold로 safe head가 멈추는 것보다 낫다.

### 4차 수정 — trh-sdk commit `df0ccb4` (Apr 27)

`MaxBlobBaseFeeGwei=0` (3차 수정)은 threshold를 비활성화했지만 근본 문제를 해결하지 못했다.

**에러 변화**: `ErrBlobBaseFeeTooHigh` → `"insufficient funds for gas * price + value"`

원인:
- threshold 비활성화 → batcher가 blob tx 제출 시도
- `BlobFeeCap = BlobFeeCapMultiplier(4) × blob_base_fee(~4.4e25 wei) = ~1.75e26 wei`
- batcher 잔액: ~0.5 ETH = 5e17 wei << 1.75e26 wei
- `eth_estimateGas` → "insufficient funds" → 여전히 safe_l2 = 0

**최종 수정**: `DataAvailabilityType = "calldata"`, `UseBlobs = false`

```go
// trh-sdk local_network.go — buildBatcherDAConfig()
// calldata를 쓰면 blob fee 계산 자체가 없음 → Sepolia blob fee 이상치 완전 우회
func buildBatcherDAConfig() (useBlobs bool, daType string) {
    return false, "calldata"
}
```

## Configuration (현재)

```bash
OP_BATCHER_DATA_AVAILABILITY_TYPE=calldata         # blob fee 우회 (Sepolia 이상치 대응)
OP_BATCHER_TXMGR_BLOB_FEE_CAP_MULTIPLIER=4        # calldata 모드에서 무시됨
OP_BATCHER_TXMGR_MAX_L1_BLOB_BASE_FEE=0           # calldata 모드에서 무시됨
```

## Behavior

- `DataAvailabilityType=calldata`: blob fee 계산 없음 → 정상 L1 calldata tx 제출 → safe_l2 진행
- `DataAvailabilityType=blobs` + `MaxBlobBaseFeeGwei=0`: blob fee 무제한 → "insufficient funds" 위험
- `DataAvailabilityType=blobs` + `MaxBlobBaseFeeGwei=50`: 50 gwei 임계값 → Sepolia 스파이크 시 safe_l2=0
