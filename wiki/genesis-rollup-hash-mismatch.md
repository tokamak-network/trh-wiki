---
updated: 2026-05-12
---

# Genesis/Rollup Hash Mismatch — op-node CrashLoopBackOff

## 증상

op-node가 시작 직후 CrashLoopBackOff 상태에 빠지며 아래 에러 반복:

```
l2_genesis_block_hash mismatch: rollup.json says 0xABCD..., but L2 node has 0x1234...
```

## 근본 원인

배포 Stage B에서 `maybeFundAAAdmin`이 `genesis.json`의 alloc 필드를 패치한다 (AA 설정 필요 시, fee token ≠ TON). alloc이 변경되면 block 0 해시가 바뀌는데, 이 때 `rollup.json`의 `genesis.l2.hash`가 재동기화되지 않아 두 파일의 해시가 어긋난다. 이후 해당 파일들이 Terraform `config-files/`를 통해 S3로 업로드되고, op-node가 이를 읽으면서 mismatch를 감지하여 충돌한다.

```
genesis.json alloc 패치 (maybeFundAAAdmin)
    ↓
block 0 해시 변경
    ↓
rollup.json genesis.l2.hash는 구버전 유지
    ↓
S3 업로드 (config-files/)
    ↓
op-node: l2_genesis_block_hash mismatch → CrashLoopBackOff
```

## 수정 (trh-sdk 18fc5d4)

`DeployAWSStageB`에 preflight check 삽입 — config-files/ 복사 전(Step 2)에 `ensureRollupGenesisHashSync` 호출.

**검사 로직** (`genesis_sync.go`):
1. `genesis.json`에서 block 0 해시를 순수 Go로 계산: `core.Genesis.ToBlock().Hash()`
2. `rollup.json`에서 `genesis.l2.hash` 읽기
3. 일치 → 통과 (정상 경로, binary 다운로드 없음)
4. 불일치 → `tokamak-deployer --base-genesis`로 `rollup.json` 재생성 후 재검증

**순수 Go 해시 계산 검증**: 3개 테스트넷 배포본(trh-testnet, trh-testnet1, trh-testnet2)에서 `core.Genesis.ToBlock().Hash()` == `rollup.json genesis.l2.hash` 실증 확인.

## 설계 결정

### 1. 순수 Go 해시 vs 매번 binary 호출

binary(`runGenerateGenesis`)는 매 호출마다 수분이 걸리고 tokamak-deployer 다운로드가 필요하다. `core.Genesis.ToBlock().Hash()`는 2개 파일 읽기 + 해시 계산 뿐이므로 정상 경로(in-sync)에서 overhead가 0에 가깝다. binary는 mismatch 감지 시에만 lazy-download한다.

### 2. OutPath에 임시 파일 사용

`runGenerateGenesis`는 `--out`(OutPath)과 `--base-genesis`(BaseGenesisPath)를 각각 받는다. Stage B에서는 OutPath = BaseGenesisPath가 동일 경로이므로, `--out` 쓰기 시 `--base-genesis` 읽기 전에 파일이 truncate된다. 임시 파일을 OutPath로 사용하고 완료 후 삭제한다.

```go
// Use a separate temp file for OutPath to avoid truncating BaseGenesisPath
tmpOut, _ := os.CreateTemp("", "genesis-sync-*.json")
defer os.Remove(tmpOut.Name())
return runGenerateGenesis(ctx, binaryPath, genesisOpts{
    OutPath:         tmpOut.Name(),   // ← temp
    BaseGenesisPath: t.genesisConfigPath(), // ← original, not truncated
    RollupOutPath:   rollupOutPath,
    ...
})
```

### 3. `genesisRegenerateFn` 인터페이스 주입

binary 없이 단위 테스트가 가능하도록 재생성 로직을 함수 타입으로 분리. `ensureRollupGenesisHashSync`는 파일 연산만 다루고, binary 의존성은 호출자가 closure로 주입한다.

## 테스트 커버리지

`genesis_sync_test.go` 10개 케이스:

| 테스트 | 검증 내용 |
|--------|---------|
| `TestComputeGenesisBlockHash_KnownFixture` | 알려진 fixture 해시가 고정 상수와 일치 |
| `TestComputeGenesisBlockHash_Deterministic` | 동일 입력 → 동일 출력 (비결정성 없음) |
| `TestComputeGenesisBlockHash_MissingFile` | 파일 없으면 에러 반환 |
| `TestReadRollupGenesisHash_ValidJSON` | 정상 rollup.json 파싱 |
| `TestReadRollupGenesisHash_InvalidJSON` | 비정상 JSON → 에러 |
| `TestReadRollupGenesisHash_MissingHash` | hash 필드 누락 → 에러 |
| `TestEnsureRollupGenesisHashSync_InSync_RegenNotCalled` | 해시 일치 시 regenerate 미호출 |
| `TestEnsureRollupGenesisHashSync_Mismatch_CallsRegenerate` | 불일치 시 regenerate 호출 후 재검증 통과 |
| `TestEnsureRollupGenesisHashSync_RegenerateError_Propagates` | regenerate 실패 시 에러 전파 |
| `TestEnsureRollupGenesisHashSync_RegenerateProducesWrongHash` | regenerate 후에도 불일치 → 에러 |

## 관련 파일

- `trh-sdk/pkg/stacks/thanos/genesis_sync.go` — 핵심 구현
- `trh-sdk/pkg/stacks/thanos/genesis_sync_test.go` — 단위 테스트
- `trh-sdk/pkg/stacks/thanos/aa_genesis.go` — alloc 패치 주체 (`maybeFundAAAdmin`)
- `trh-sdk/pkg/stacks/thanos/deploy_chain.go` — preflight 삽입 지점 (Stage B Step 2)
