---
updated: 2026-05-06
related:
  - "[[l2-output-oracle-uninitialized]]"
  - "[[cross-trade]]"
tags: [troubleshooting, aws, crosstrade, optimism-portal]
---

# OptimismPortalProxy Uninitialized → CrossTrade Deposit Tx Revert

## 증상

AWS 배포 후 CrossTrade auto-install 시 L2 컨트랙트 배포 단계에서 revert:

```
autoInstallCrossTradeAWS: L2 contract deployment failed:
  L2CrossTrade pair deployment failed: step 1 failed:
    deposit creation tx reverted (tx: 0x6a6d1a1f..., gas used: 326060)
```

`cast` 확인:
```bash
cast call $PORTAL "systemConfig()" --rpc-url $L1_RPC
# → 0x0000000000000000000000000000000000000000   ← zero = 미초기화
```

---

## 근본 원인

tokamak-deployer는 `upgrade(proxy, impl)`만 호출하고 `initialize()`를 **절대 호출하지 않는다**.

결과적으로 `OptimismPortalProxy.systemConfig = address(0)`.

`depositTransaction()`은 `metered(_amount)` modifier를 통해 실행된다:

```
depositTransaction()
  → metered(_amount)
    → _metered() [post-execution]
      → _resourceConfig()
        → ISystemConfig(systemConfig).resourceConfig()
        → systemConfig = address(0) → address(0).resourceConfig() → empty bytes
        → ABI decode ResourceConfig → REVERT
```

함수 본문(실제 deposit 저장)은 성공하지만, modifier의 post-execution hook에서 revert가 발생하므로 트랜잭션 전체가 취소된다.

같은 이유로 `SystemConfig`, `L1CrossDomainMessenger`도 미초기화 상태이며, op-node가 배치 derivation을 못하거나 CDM 메시지 패싱이 실패할 수 있다.

---

## 영향 범위

| 컨트랙트 | 결과 |
|---------|------|
| OptimismPortal | `depositTransaction()` 항상 revert → CrossTrade L2 배포 불가 |
| SystemConfig | `batcherHash=0, gasLimit=0` → op-node 배치 derivation 불가 |
| L1CrossDomainMessenger | `portal=0` → CDM 메시지 패싱 실패 |
| L2OutputOracle (L2OO 모드) | `proposer=address(0)` → op-proposer 출력 제출 불가 |
| DisputeGameFactory (fault proof 모드) | 게임 impl 미등록 → FaultDisputeGame 생성 불가 |
| OptimismPortal2 (fault proof 모드) | `disputeGameFactory=0` → Portal2 기능 불가 |

---

## 수정 (2026-05-06)

**파일:** `trh-sdk/pkg/stacks/thanos/deploy_chain.go`

`deployNetworkToAWS()` 함수에 Step 8.2.6 추가 — L2 체인 노드 배포 후, backup/bridge 설치 전.

```go
// Step 8.2.6: initSystemConfig → initL1CrossDomainMessenger →
//   (L2OO): initOptimismPortal + initL2OutputOracle
//   (fault proof): initDisputeGameFactory + initOptimismPortal2
```

이미 `local_network.go`에 존재하는 동일한 init 함수들을 AWS 경로에서도 호출한다.

모든 init 함수에는 idempotency guard가 있어 재실행 시 이미 초기화된 컨트랙트는 skip한다.

---

## 관련 파일

| 파일 | 역할 |
|------|------|
| `trh-sdk/pkg/stacks/thanos/deploy_chain.go:560-709` | Step 8.2.6 — proxy init sequence (AWS path) |
| `trh-sdk/pkg/stacks/thanos/local_network.go:192-358` | 동일 패턴의 로컬 경로 참조 구현 |
| `trh-sdk/pkg/stacks/thanos/deploy_chain.go:1300+` | initSystemConfig, initOptimismPortal, initDisputeGameFactory 등 |

---

## 유사 버그

- [[l2-output-oracle-uninitialized]] — 동일 패턴: tokamak-deployer upgrade-only → proposer=address(0)
