---
updated: 2026-04-15
component: tokamak-thanos / op-batcher
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

## Fix (tokamak-thanos `main`, commit `8e67bbce`)

| 변경 | 파일 |
|------|------|
| `retry.Unrecoverable` 추가 — 30회 retry 없이 즉시 중단 | `op-service/retry/operation.go` |
| `BlobFeeCapMultiplier` / `MaxBlobBaseFee` CLI 플래그 추가 | `op-service/txmgr/cli.go` |
| `(m *SimpleTxManager).calcBlobFeeCap()` — 배수 설정화 (기본 4×) | `op-service/txmgr/txmgr.go` |
| `craftTx`: 임계값 선검사 + `finishBlobTx` 직전 blob base fee 재조회 | `op-service/txmgr/txmgr.go` |
| `ErrBlobBaseFeeTooHigh` sentinel + driver Warn 로그 | `op-batcher/batcher/driver.go` |

## Configuration

`op-batcher` 환경 변수:

```bash
OP_BATCHER_DATA_AVAILABILITY_TYPE=blobs           # calldata 우회 해제
OP_BATCHER_TXMGR_BLOB_FEE_CAP_MULTIPLIER=4        # 기본 4× (구 하드코딩 2×)
OP_BATCHER_TXMGR_MAX_L1_BLOB_BASE_FEE=50          # 50 gwei 초과 시 제출 일시 중단
```

trh-sdk `local-compose.yml.tmpl`에 자동 주입됨 (commit `13e1465`).

## Behavior After Fix

- blob base fee < 50 gwei: 4× cap으로 정상 제출
- blob base fee ≥ 50 gwei: `ErrBlobBaseFeeTooHigh` → retry 없이 즉시 반환 → 프레임 재큐 → 다음 ticker 틱에서 재시도
- 스파이크 해소 후 자동 재개

## Rollback

스파이크가 장기 지속될 경우 임시 우회:
```bash
OP_BATCHER_DATA_AVAILABILITY_TYPE=calldata
```
(calldata는 blob fee를 사용하지 않으므로 스파이크 영향 없음)
