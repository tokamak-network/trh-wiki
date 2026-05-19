---

updated: 2026-05-19
sources: []
related:
  - "[[gaming-full-preset-genesis-hash-mismatch]]"
tags: [troubleshooting]
---
# AnchorStateRegistry — setInitialAnchorState 누락 (RC3)

## 증상

Gaming/Full preset 배포 시 `initGenesisAnchorState` 단계에서 다음 오류 발생:

```
setInitialAnchorState pre-flight simulation failed — AnchorStateRegistry at 0x... 
likely lacks the setInitialAnchorState function
```

또는 op-proposer 로그에서:

```
AnchorRootNotFound
```

## 근본 원인

`tokamak-deployer deploy-contracts`는 embed된 pre-compiled 바이트코드를 사용하여 `AnchorStateRegistry` impl을 배포한다. `patchAnchorStateRegistry()`는 `.sol` 소스 파일만 패치하며 — 이는 cannon prestate 빌드용이다 — 실제 deployer가 사용하는 embedded 바이트코드에는 영향을 주지 않는다.

따라서 배포된 `AnchorStateRegistry` impl은 항상 `setInitialAnchorState` 함수가 없으며, 이를 호출하면 revert된다.

## 수정 (trh-sdk commit 339c882)

`initGenesisAnchorState`의 Guard B가 실패하면 에러를 반환하는 대신 `bootstrapAnchorStateViaStorageSetter`를 호출한다.

### StorageSetter Fallback 절차

scripts/fix-anchor-state-registry.mjs와 동일한 패턴:

1. **ProxyAdmin owner EOA 검증** — contract 소유자(Gnosis Safe 등)면 실패
2. **StorageSetter 배포** — `setBytes32(bytes32,bytes32)` 함수를 가진 임시 컨트랙트
3. **`ProxyAdmin.upgradeAndCall(proxy, storageSetter, setBytes32(slot, root))`** — 프록시 구현을 StorageSetter로 업그레이드하면서 동시에 storage 쓰기
4. **Storage slot 검증** — 실제로 써졌는지 확인
5. **`ProxyAdmin.upgrade(proxy, originalImpl)` 복원** — LOUD-FAIL (실패 시 프록시가 StorageSetter에 stuck)

### Storage Slot 계산

`anchors[gameType].root` slot = `keccak256(abi.encode(uint256(gameType), uint256(1)))`

gameType=0 (CANNON)의 경우: `0xa6eef7e35abe7026729641147f7915573c7e97b47efa546f5f6e3230263bcb49`

> **전제**: `anchors` mapping이 현재 impl 바이트코드의 storage slot 1에 위치해야 함.

### Guard A 멱등성

Fallback 성공 후 `initGenesisAnchorState`가 재호출되면 Guard A의 `anchors[gameType].root != 0` 체크로 즉시 skip된다.

## 관련 컨텍스트

- **RC1**: Gaming/Full preset genesis hash mismatch → [[gaming-full-preset-genesis-hash-mismatch]]
- **RC2**: DRB peer ID mismatch — RC1+RC3 해결 시 자동 해소 (`orchestrateDRBOperators()` 정상 실행)
- **수동 스크립트**: `scripts/fix-anchor-state-registry-*.mjs` (배포 후 수동 복구용)
