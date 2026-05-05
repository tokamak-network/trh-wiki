# AA / EIP-7702 두 가지 Root Cause 수정

**발생 환경**: AWS L2 testnet (full preset, AA 활성화)  
**증상**: 배포 후 AA 기능 4개 오류 동시 발생

---

## RC1 — AA 백그라운드 고루틴이 L2RpcUrl을 받지 못하는 threading bug

### 증상

- `aa_price_updater`: `dial tcp: connection refused` (SimplePriceOracle 업데이트 실패)
- `aa_refill_monitor`: EntryPoint 잔액 조회 실패
- `aa_bridge`: L2 잔액 조회 실패
- `initGenesisAnchorState`, DRB readiness check: L2 연결 불가

모두 같은 원인: **`http://host.docker.internal:8545`** (local fallback)로 다이얼 시도.

### 근본 원인

`ThanosStack`은 `deployConfig.L2RpcUrl`을 갖고 있지만, `RunAAOperator`가 `AAOperatorConfig`를 구성할 때 `L2RpcUrl`을 누락했다. 이로 인해 AA 백그라운드 고루틴 전체가 `localL2RPCURL()`로 폴백됨.

### 수정 (trh-sdk `51e3a22`)

`aa_operator.go`: `AAOperatorConfig`에 `L2RpcUrl string` 추가, `RunAAOperator`/`RunAAOperatorFromConfig`에서 전달.

모든 AA 함수 (`aa_price_updater.go`, `aa_refill_monitor.go`, `aa_bridge.go`, `local_network.go`)에 override 패턴 적용:

```go
l2URL := localL2RPCURL()
if t.deployConfig.L2RpcUrl != "" {
    l2URL = t.deployConfig.L2RpcUrl
}
```

---

## RC2 — `NewL2Genesis`가 `IsthmusTime`을 체인 config에 포함하지 않음

### 증상

```
pool not yet in Prague
```

EIP-7702 (SetCode tx, type 0x04) 트랜잭션을 op-geth가 거부.

### 근본 원인

`op-chain-ops/genesis/genesis.go`의 `NewL2Genesis`가 체인 config에 `IsthmusTime`을 설정하지 않음. Isthmus = L2 측 Prague 하드포크. 이 필드 없이 genesis가 생성되면 이후 어떤 블록에서도 Prague(EIP-7702)가 활성화되지 않음.

추가로 `go.mod`의 `replace github.com/ethereum/go-ethereum` 지시자가 **로컬 경로** (`../tokamak-thanos-geth`)를 가리키고 있어 CI/CD 클론 환경에서 빌드 불가.

### 수정 (tokamak-thanos `8420273d24`)

1. `op-chain-ops/genesis/genesis.go`: `NewL2Genesis`에 `IsthmusTime` 추가

   ```go
   FjordTime:               config.FjordTime(block.Time()),
   IsthmusTime:             config.IsthmusTime(block.Time()),  // 추가
   InteropTime:             config.InteropTime(block.Time()),
   ```

2. `go.mod`: replace 지시자를 로컬 경로 → 원격 pseudo-version으로 변경

   ```
   replace github.com/ethereum/go-ethereum => github.com/tokamak-network/tokamak-thanos-geth v0.0.0-20260502144003-25d0c60d53c4
   ```

   `IsthmusTime`은 tokamak-thanos-geth commit `cb69272ba` (2026-04-02)에 추가됨.

3. `op-chain-ops/deployer/deployer.go`: `TerminalTotalDifficultyPassed: true` 제거 (해당 필드는 tokamak-thanos-geth Nov 2025에 제거됨)

4. `go.sum`, `go.work.sum`: 새 버전 해시 추가

### 주의사항

- `IsthmusTime`과 `TerminalTotalDifficultyPassed`가 tokamak-thanos-geth에 **동시에 존재하는 버전은 없음**. `IsthmusTime` 추가 커밋(`cb69272ba`, Apr 2026)은 이미 `TerminalTotalDifficultyPassed` 제거 이후 버전임.
- `GOWORK=off GOPROXY=direct go mod download github.com/ethereum/go-ethereum`으로 `go.sum`에 새 버전 해시를 추가해야 workspace 미사용 환경에서도 빌드 가능.
