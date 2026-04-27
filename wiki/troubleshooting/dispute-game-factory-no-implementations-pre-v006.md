# DisputeGameFactory — no game implementations (pre-v0.0.6 stacks)

## 증상

AnchorStateRegistry anchor root 0x0 문제를 StorageSetter fallback으로 해결한 뒤에도
op-proposer가 계속 실패:

```
op-proposer: estimating gas: execution reverted
```

또는:

```
DisputeGameFactory.create() reverted — no implementation for game type 0
```

`gameImpls(0)` 조회 시 `0x0000...0000` 반환.

## 근본 원인 — Bug #8 (tokamak-deployer < v0.0.6)

`tokamak-deployer v0.0.5` 이하에서는 `deploy-contracts` 명령에 `--fault-proof` 플래그가 없으면
fault proof 관련 배포 단계(27-32)가 **조용히(silently) 스킵**되었다.

스킵된 단계:
- MIPS (Cannon VM) 배포
- PreimageOracle 배포
- FaultDisputeGame implementation 배포
- PermissionedDisputeGame implementation 배포
- `DisputeGameFactory.setImplementation(gameType, impl)` 호출

v0.0.6에서 `--fault-proof` 플래그가 추가되면서 이 단계들이 기본 실행된다.
그 이전 버전으로 배포된 스택은 DisputeGameFactory에 게임 구현이 없는 상태로 남는다.

**확인 방법**: 스택 `deploy-output.json`에 FaultDisputeGame, MIPS, PreimageOracle 주소가 없으면 Bug #8 스택.

## 영향을 받는 스택

- `7640669c-980a-4c35-93ee-c6f08c5e3fcb` (Sepolia testnet, 2026-04-27 확인)
  - deploy-output.json: 12개 컨트랙트만 존재 (fault proof 컨트랙트 전부 누락)
  - settings.json: `enable_fraud_proof: true` 설정되어 있으나 배포 안 됨

## 해결 방법

### 옵션 A — 수동 fault proof 컨트랙트 배포 (운영 중 스택 유지)

v0.0.6+ deployer 바이너리로 fault proof 단계(27-32)만 재실행:

```bash
tokamak-deployer deploy-contracts --fault-proof \
  --skip-steps 1-26 \
  --deploy-config <config> \
  --l1-rpc <rpc>
```

> ⚠️ `--skip-steps` 지원 여부 확인 필요. 지원 안 되면 옵션 B 사용.

### 옵션 B — 스택 재배포 (권장)

v0.0.6+ tokamak-deployer로 전체 재배포. L2 체인데이터 초기화 필요.

```bash
# trh-sdk deployer에서
make deploy STACK_ID=<id> DEPLOYER_VERSION=v0.0.6
```

## StorageSetter bytecode 버그 수정 (trh-sdk commit e396bb1)

동일 세션에서 발견된 관련 버그: `storageSetterBytecode`가 14바이트 부족했다.

- **원인**: offset 0x191 지점에서 두 개의 함수 디스패처 stub 엔트리(`0x02f9`, `0x032e`)가 누락됨
- **증상**: setBytes32 호출 시 `InvalidJump` — JUMP 타겟이 14바이트씩 밀려서 유효하지 않은 위치를 가리킴
- **수정**: 955바이트 → 969바이트 (누락된 14바이트 복원)

StorageSetter fallback은 이미 올바르게 배포된 외부 StorageSetter(예: `0x7213A04B7bC618BA9688385D0792ACA3CA2356e4`)를 재사용하는 방식으로 Bug #8 스택을 수동 복구할 수 있다. (`scripts/fix-anchor-state-registry-*.mjs` 참조)

## originalImpl EIP-1967 fallback (trh-sdk commit e396bb1)

`deploy-output.json`에 `AnchorStateRegistry` impl 주소가 없는 스택에서
`bootstrapAnchorStateViaStorageSetter`가 실패하는 문제도 함께 수정됨.

수정 후: `originalImpl` 파라미터가 zero address이면 EIP-1967 impl 슬롯
(`0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`)에서 읽어서 자동 복원.

## 관련 문서

- [[anchor-state-registry-missing-set-initial-anchor-state]] — StorageSetter fallback 절차
- [[op-node-genesis-l1-block-zero]] — 함께 나타나는 또 다른 배포 버그 (SystemConfig.startBlock)
