---
updated: 2026-05-09
related:
  - "[[cross-trade]]"
  - "[[op-node-pectra-blob-base-fee]]"
tags: [troubleshooting, aws, crosstrade]
---

# CrossTrade AWS Auto-Install Hang (InProgress timeout)

## 증상

EFP-02 (또는 CrossTrade 통합 폴링) 테스트가 정확히 30분 후 timeout:

```
Timeout waiting for: CrossTrade integration to complete (after 121 attempts, 1800000ms)
```

백엔드 로그에는 진행 상황이 없고, crossTrade 통합 상태가 `InProgress`에서 변하지 않음.

---

## 근본 원인

CrossTrade auto-install goroutine이 `context.Background()`로 실행되기 때문에, forge가 L2 RPC에 연결하려고 무한 대기해도 OS/Go 런타임이 개입하지 않는다.

```
deployment.go:482
  go s.integrationMgr.AutoInstallCrossTradeAWS(
      context.Background(),   ← 취소 불가
      ...
  )
    ↓
cross_trade.go (SDK)
  forge script ... --rpc-url $L2_RPC --broadcast
    ← L2 RPC가 down이면 forge가 hang
    ← context.Background() 이므로 kill 안 됨
```

---

## 트리거 조건

아래 조건 중 하나라도 해당되면 hang 발생:

| 조건 | 원인 |
|------|------|
| op-geth pod ImagePullBackOff | L2 RPC → 503; forge 무한 대기 |
| tokamak-thanos-stack clone race | SDK가 fix 이전 스크립트로 clone → `nightly-nightly` 이미지 |
| L2 체인이 아직 sync 중 | forge script 실행 시 L2 RPC 응답 없음 |

### Race condition 상세 (EFP run 11, 2026-05-02)

- b3a5049 (op-geth 이미지 태그 fix) push: **23:20:54**
- EFP run 11 시작: **~12:22** (push 전)
- SDK가 tokamak-thanos-stack `main`을 clone → old script → `nightly-nightly` 이미지

tokamak-thanos-stack을 deploy 시점에 최신 main으로 clone하기 때문에,
fix push 전에 deploy가 시작됐으면 old script로 clone됨.

---

## 수정 (2026-05-03)

### Fix 1: goroutine에 50분 context timeout 추가
**파일:** `trh-backend/pkg/services/thanos/deployment.go`

```go
ctxCT, cancelCT := context.WithTimeout(context.Background(), 50*time.Minute)
go func() {
    defer cancelCT()
    ...
    s.integrationMgr.AutoInstallCrossTradeAWS(ctxCT, ...)
}()
```

forge가 50분 안에 응답 없으면 context 취소 → `ExecuteCommandStream` → `exec.CommandContext` → forge 프로세스 kill.

### Fix 2: L2 RPC readiness check 추가
**파일:** `trh-backend/pkg/services/thanos/deployment.go` (새 함수 `waitForL2RPC`)

goroutine 시작 후 forge 실행 전, L2 RPC(`eth_blockNumber`)가 응답할 때까지 최대 10분 대기 (30초 간격).
응답 없으면 goroutine이 명시적 오류 로그를 남기고 종료 (silent hang 대신).

### Fix 3: 테스트 timeout 50분으로 증가
**파일:** `trh-platform/tests/e2e/electron-full-preset-features.live.spec.ts`

```typescript
const CROSSTRADE_INSTALL_TIMEOUT_MS = 50 * 60 * 1000; // was 30
```

backend goroutine timeout(50분)과 동기화.

---

## 재현 방지

- **b3a5049**: tokamak-thanos-stack op-geth 이미지 태그 fix (`${op_geth_image_tag}` 직접 사용)
- deploy 전에 반드시 tokamak-thanos-stack main이 최신인지 확인
- L2 RPC readiness check가 op-geth ImagePullBackOff를 조기 감지해 로그에 명시적 에러 남김

---

## 관련 파일

| 파일 | 역할 |
|------|------|
| `trh-backend/pkg/services/thanos/deployment.go:478-507` | CrossTrade goroutine 시작, `waitForL2RPC` |
| `trh-sdk/pkg/stacks/thanos/cross_trade.go:108,186` | `forge script --rpc-url $L2_RPC --broadcast` |
| `trh-sdk/pkg/utils/command.go` | `ExecuteCommandStream` — context 취소 시 forge kill |
| `tokamak-thanos-stack/terraform/thanos-stack/scripts/generate-thanos-stack-values.sh` | op-geth 이미지 태그 생성 |

---

## 2차 버그: 이중 배포로 인한 nonce 충돌 (2026-05-09 발견)

### 증상

배포 로그에 `"↳ cross-trade: deploying L2 contracts via deposit tx"` 메시지가 **두 번** 나타남.
첫 번째 배포는 성공하지만 두 번째는 실패:

```
2026-05-09T12:05:33  ↳ cross-trade: deploying L2 contracts via deposit tx...
  → contract deployed at 0x5537... (attempt 42/60)
  → L2 CrossTrade contracts deployed: proxy=0x5537... l2l2proxy=0x23249...
  → ✅ CrossTrade deployed

2026-05-09T12:23:42  ↳ cross-trade: deploying L2 contracts via deposit tx...
  → ERROR: L2 contract deployment failed: step 1 L2 verification failed:
           contract at 0x53D0... not deployed after 120s
```

crossTradeUrl 등 metadata 필드가 NULL인 채로 배포 완료.

### 근본 원인

두 개의 코드 경로가 모두 `AutoInstallCrossTradeAWS`를 호출:

1. **SDK `installPresetModules`** (`deploy_chain.go:2391`): `DeployAWSStageBInfra` 도중 호출. L2 contracts를 성공적으로 배포하지만 **백엔드 DB `integrations` 레코드를 업데이트하지 않음** (여전히 `Pending` 상태).
2. **백엔드 goroutine** (`deployment.go:499-531`): `executeDeploymentsAWSParallel` 반환 후, `GetIntegrationByStatus(Pending)`이 여전히 Pending 레코드를 발견 → goroutine 실행 → **동일 SDK 함수 두 번째 호출**.

두 번째 호출 시 deployer nonce가 이미 소진되어, L1 deposit tx로 예측한 L2 contract 주소가 달라짐 → 120초 대기 후 실패.

### 수정 (2026-05-09, trh-sdk@0c62dc9)

**파일:** `trh-sdk/pkg/stacks/thanos/deploy_chain.go`

SDK `installPresetModules`에서 AWS CrossTrade 브랜치를 제거. 백엔드 goroutine이 integration record state machine(Pending → InProgress → Completed/Failed)을 관리하는 유일한 소유자가 됨.

```go
// Before: SDK도 AutoInstallCrossTradeAWS를 호출
if modules["crossTrade"] {
    if t.deployConfig.K8s != nil {  // AWS
        t.AutoInstallCrossTradeAWS(ctx)  // ← 제거
    } else {
        t.logger.Info("ℹ️  Run 'trh install cross-trade'...")
    }
}

// After: 로컬 안내 메시지만 남김
if modules["crossTrade"] && t.deployConfig.K8s == nil {
    t.logger.Info("ℹ️  Run 'trh install cross-trade'...")
}
```

**설계 원칙**: SDK는 infra를 프로비저닝하고 결과를 반환하는 역할. 상태 머신(Pending→Completed)을 관리하는 것은 백엔드의 책임. SDK가 직접 백엔드 DB를 모르는 채로 통합 레코드 기반 흐름에 개입해서는 안 됨.
