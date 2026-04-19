# Gaming/Full Preset: Genesis Hash Mismatch (RC1)

## 증상

Gaming/Full preset 배포 후 op-node 시작 시 다음과 같은 오류가 발생:

```
genesis hash mismatch: <hash-A> != <hash-B>
```

또는 `deploy-local-infra` 단계에서 `initGenesisAnchorState` pre-flight simulation이 revert되어 실패.

## 근본 원인

`DeployContracts()` 파이프라인의 실행 순서 문제:

1. `runGenerateGenesis()` → rollup.json에 `genesis.l2.hash` 기록 (hash-A)
2. `maybeInjectDRB()` → genesis.json alloc에 DRB predeploy 추가 (블록 해시 변경)
3. `maybeFundDRBRegulars()` → genesis.json alloc에 DRB 운영자 잔액 추가 (블록 해시 추가 변경)
4. op-node가 genesis.json으로부터 실제 hash-B를 계산 → rollup.json의 hash-A와 불일치 → crash

**핵심**: `tokamak-deployer generate-genesis`가 `core.Genesis.ToBlock().Hash()`로 hash를 계산하지만,
trh-sdk의 DRB 주입 함수들이 그 이후에 genesis.json을 수정하기 때문에 rollup.json 해시가 stale 상태가 된다.

## 수정 (trh-sdk)

`deploy_contracts.go`에 RC1 fix 추가 (commit `323489c`):

Gaming/Full preset에서 `maybeFundDRBRegulars()` 이후, `--base-genesis` 플래그를 사용해 두 번째 `generate-genesis`를 실행:

```go
if constants.PresetModules[t.deployConfig.Preset]["drb"] {
    rollupPath := filepath.Join(t.deploymentPath, "rollup.json")
    runGenerateGenesis(ctx, binaryPath, genesisOpts{
        DeployOutputPath: stagedAddrPath,
        ConfigPath:       deployConfigFilePath,
        OutPath:          genesisPath,
        RollupOutPath:    rollupPath,
        BaseGenesisPath:  genesisPath, // post-DRB genesis.json을 base로 사용
    }, t.output)
}
```

**`--base-genesis` 효과**: op-node를 다시 실행하지 않고, 수정된 genesis.json으로부터 블록 해시를 재계산해 rollup.json을 in-place 업데이트.

**Post-processing 멱등성 확인**:
- USDC inject: proxy code가 이미 있으면 skip (명시적 idempotency check)
- MTP inject: 단순 overwrite (idempotent)
- L1Block patch: 단순 overwrite (idempotent)

## 관련 이슈

- **RC2 (DRB peer ID 불일치)**: RC1 + RC3이 해결되면 자연스럽게 해결됨 (orchestrateDRBOperators가 정상 실행되면 peer ID 파일이 생성됨)
- **RC3 (AnchorStateRegistry `setInitialAnchorState` 누락)**: 별도 이슈 — tokamak-deployer가 embedded bytecode를 사용하므로 `.sol` 패치 무효. 수동 workaround: `scripts/fix-anchor-state-registry-<deploymentId>.mjs`

## `--base-genesis` 플래그 동작 원리

`tokamak-deployer generate-genesis --base-genesis <file>`:
- `<file>`을 base genesis로 복사 (op-node `genesis l2` 호출 생략)
- USDC, MTP, L1Block post-processing 적용 (모두 idempotent)
- `--rollup-out <path>`가 있고 파일이 존재하면 rollup.json의 `genesis.l2.hash`를 in-place 업데이트

**주의**: `--rollup-out`은 existing rollup.json을 업데이트만 하며, 파일이 없으면 silently skip.

## 관련 파일

- `trh-sdk/pkg/stacks/thanos/deploy_contracts.go` — RC1 fix 위치
- `trh-sdk/pkg/stacks/thanos/drb_genesis.go` — `maybeInjectDRB`, `maybeFundDRBRegulars`
- `tokamak-thanos/cmd/tokamak-deployer/internal/genesis/rollup.go` — `updateRollupGenesisHash`
- `tokamak-thanos/cmd/tokamak-deployer/internal/genesis/generator.go` — `Generate()` step 순서
