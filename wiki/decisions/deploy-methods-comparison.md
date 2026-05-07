---
title: Deploy.s.sol vs tokamak-deployer — L1 배포 방식 비교
date: 2026-04-18
status: final
tags: [deployment, L1, L2-genesis, foundry, tokamak-deployer, trh-sdk]
---

# Deploy.s.sol vs tokamak-deployer — L1 배포 방식 비교

## 0. TL;DR

TRH L2 체인 배포의 L1 컨트랙트 배포 엔진은 2026-04-16 (`trh-sdk df52538`) 에 **Foundry 기반 `Deploy.s.sol` + `start-deploy.sh`** 경로에서 **Go 네이티브 `tokamak-deployer` CLI** 경로로 전환되었다. 체감 배포 시간이 **25–30 분 → 6–8 분**으로 줄었고, 재시도/로깅/버전 고정이 처음으로 운영 가능 수준이 되었다. 대신 Solidity VM 시뮬레이션·`--resume`·`reuseDeployment` 같은 forge 고유 기능은 포기했고, **L2 Genesis 단계는 여전히 forge + op-node** 조합을 쓴다.

## 1. 배경 & 전환 맥락

기존 Foundry 경로의 운영상 통증은 세 가지였다.

1. **부트스트랩 비용** — trh-sdk는 배포할 때마다 `tokamak-thanos` 전체(~1-2 GB)를 clone 하고, `pnpm install` / `make submodules` / `cannon-prestate` / `op-node build` / `forge build` / `core-utils` / `sdk build` 를 순차 실행했다(`start-deploy.sh:182-318`). 정상 경로에서도 10-15분이 소요됐고 빌드 실패로 배포가 중단되는 경우가 빈번했다.
2. **가스 가격 불안정** — `forge script ... --broadcast --slow` 는 매 TX가 Foundry 내부에서 즉흥 가스 산정을 수행했다. Sepolia에서 TX 간 가격이 드리프트하면서 스턱-TX 가 반복적으로 발생했고, `--resume` 재실행이 빈번했다.
3. **관측 불가** — forge stdout 만으로는 32-step 중 어디서 멈췄는지, 왜 멈췄는지를 사실상 알 수 없었다. 실패 시 tx hash 조차 잡히지 않는 경우가 있었다.

전환은 두 단계로 이뤄졌다: **`df52538` (2026-04-16)** 에서 L1 배포 파이프라인을 교체했고, **`230cdb8` (2026-04-17)** 에서 가스 전략을 `v0.0.5` 고정 가스 가격으로 단순화했다.

> **중요 — 현재 전환 상태는 "완전 마이그레이션" 이 아닌 "하이브리드"**. TRH 주력 배포 엔드포인트 `POST /stacks/thanos/preset-deploy` (`trh-backend/pkg/services/thanos/preset_deploy.go:127`) 는 `EnableFaultProof: true` 로 하드코딩돼 있어 **Preset 배포 100% 가 fault-proof ON**. 따라서 tokamak-deployer v0.0.5 로 전환된 경로는 "fault-proof OFF 인 개발자용 CLI 경로" 뿐이고, Platform/UI 에서 트리거되는 실배포는 여전히 **tokamak-thanos clone + forge 빌드 + cannon prestate 빌드 + AnchorStateRegistry 소스 패치** 를 요구한다. 아래 모든 비교는 이 하이브리드 현실을 전제로 읽어야 한다.

## 2. 상위 요약 — 핵심 비교 축

| 축 | 기존 (Deploy.s.sol + start-deploy.sh) | 신규 (tokamak-deployer v0.0.5) |
|---|---|---|
| 부트스트랩 | 전체 repo clone + 의존성 빌드 (pnpm, submodule, forge, go) | GitHub Releases 에서 **OS-specific 바이너리 tar.gz 1개** 다운로드 (~30 MB), `.trh/bin/` 캐시 |
| L1 배포 엔진 | `forge script Deploy.s.sol:Deploy --broadcast --slow --legacy` (Solidity VM 시뮬레이션 후 broadcast) | Go `ethclient` direct TX, 26/32 step 명시적 nonce 관리 |
| 컨트랙트 아티팩트 | 런타임에 `forge-artifacts/` 재생성 필요 | `//go:embed deploy-artifacts/` — 17개 JSON 을 바이너리 컴파일 타임에 내장 |
| 가스 가격 | 호출자가 `--with-gas-price` 전달 시 고정, 미전달 시 forge 자체 산정 (TX 별 드리프트 가능) | **시작 시 `resolveGasPrice` 1회** → 모든 26-32 TX 에 재사용, floor 1 Gwei / ceil 100 Gwei / 기본 ×2 배 멀티플라이어, `TOKAMAK_DEPLOY_GAS_PRICE` env 오버라이드 |
| 재시도 / 스턱 TX | `--slow` (nonce 순차) + forge 재시도 플래그 (`--fork-retries 10`), 세션 중단 시 `--resume` | `sendAndWaitMined`: 3 attempts × 180 s, 실패 시 1.25× 가스 bump + **동일 nonce 로 replacement TX**, `underpriced`/`already known` 에러는 재시도 신호로 처리 |
| 로깅 | forge stdout (진행 스텝, tx hash 가 일관되게 노출되지 않음) | 50+ `[deployer]` prefix 로그: `Step X/Y`, broadcasting hash, block number, ✓/✗ 표식, 동적 스텝 카운터 |
| 버전 고정 | 레포 SHA 로만 (빌드 결과는 환경 의존) | **`TokamakDeployerVersion = "v0.0.5"` 상수** (trh-sdk 측 pin), goreleaser 로 4 플랫폼 바이너리 + checksum |
| FFI 샌드박스 | `CONTRACT_ADDRESSES_PATH` 가 contracts-bedrock 루트 아래여야 함 (/tmp 거부) — `start-deploy.sh` 전체가 해당 제약 안에서 동작 | L1 배포 단계는 샌드박스 밖. **L2Genesis 단계에만 동일 제약 잔존** → `prepareL2GenesisInputs()` 가 staging 수행 |
| L2 Genesis 경로 | `start-deploy.sh generate` = forge L2Genesis + op-node genesis l2 (한 bash 함수) | 3-step 분리: (1) forge L2Genesis → state-dump (2) op-node genesis l2 → base genesis (3) **deployer 후처리 5-step** (DRB inject, USDC inject, MultiTokenPaymaster inject, L1Block Isthmus patch, rollup hash update) |
| 실측 배포 시간 | Sepolia 10-15분 + 빌드 10-15분 = **총 ~25-30분** | Sepolia **5m47s** (wiki 측정치) + 바이너리 다운로드 수 초 = **총 ~6-8분** (*fault-proof OFF 기준, CLI 경로. Preset 경로는 fault-proof ON 이라 clone+빌드가 남아 ~15-20분*) |
| Fault-proof 지원 범위 | forge + Safe wallet + cannon prestate 풀 체인: DisputeGameFactory/AnchorStateRegistry/DelayedWETH/PermissionedDelayedWETH/ProtocolVersions 전부 배포·initialize·setImplementation·transferOwnership. `_upgradeAndCallViaSafe` 를 통한 Safe multi-sig 실행. | **반쪽 포팅**: DisputeGameFactoryProxy + AnchorStateRegistryProxy 의 **deploy + plain upgrade 까지만** (`contracts.go:525-584`). initialize·setImplementation·DelayedWETH·ProtocolVersions·Safe wallet 실행 은 **여전히 forge 경로** (trh-sdk 가 tokamak-thanos clone 후 필요한 단계를 별도 실행하는 **하이브리드 구성**) |

## 3. 운영 가이드 (최소 재현 절차)

### 3.1 기존 (Foundry) 경로

```bash
# trh-sdk 구버전 (df52538^) 이 자동 실행하던 절차를 재현
cd tokamak-thanos
pnpm install && make submodules && make op-node && make cannon-prestate
cd packages/tokamak/contracts-bedrock && forge clean && forge build && cd -

cd packages/tokamak/contracts-bedrock/scripts
bash start-deploy.sh deploy -e .env -c deploy-config.json
# ↓ 내부: forge script Deploy.s.sol:Deploy \
#         --private-key $GS_ADMIN_PRIVATE_KEY \
#         --broadcast --rpc-url $L1_RPC_URL \
#         --slow --legacy --non-interactive [--with-gas-price $GAS_PRICE]

bash start-deploy.sh generate -e .env -c deploy-config.json
# ↓ 내부: forge script L2Genesis.s.sol  + op-node genesis l2
```

- **재개**: `bash start-deploy.sh redeploy ...` — forge `--resume` 사용
- **산출물**: `deployments/<chainId>-deploy.json` (address.json 형식), `build/genesis.json`, `build/rollup.json`
- **환경 변수 계약**: `GS_ADMIN_PRIVATE_KEY`, `L1_RPC_URL`, `GAS_PRICE`, `IMPL_SALT` (자동 생성), `DEPLOY_CONFIG_PATH`

### 3.2 신규 (tokamak-deployer) 경로

```bash
# (a) 바이너리 확보 — trh-sdk 는 ensureTokamakDeployer() 가 ~/.trh/bin/ 에 캐시
VERSION=v0.0.5 PLATFORM=darwin-arm64
curl -L "https://github.com/tokamak-network/tokamak-thanos/releases/download/tokamak-deployer/${VERSION}/tokamak-deployer-${PLATFORM}.tar.gz" \
  | tar -xz

# (b) L1 배포 — 26/32 step, ~6분
./tokamak-deployer deploy-contracts \
  --l1-rpc      "$SEPOLIA_RPC" \
  --private-key "$DEPLOYER_KEY" \
  --chain-id    "$L2_CHAIN_ID" \
  --gas-price   "$SUGGESTED_X2_WEI" \
  --out         deploy-output.json

# (c) L2 genesis — 3 단계 (forge L2Genesis → op-node → deployer 후처리)
forge script scripts/L2Genesis.s.sol:L2Genesis --rpc-url "$SEPOLIA_RPC"
op-node genesis l2 --deploy-config ... --l1-deployments ... --l2-allocs state-dump-*.json \
  --outfile.l2 genesis-base.json --outfile.rollup rollup.json --l1-rpc "$SEPOLIA_RPC"
./tokamak-deployer generate-genesis \
  --deploy-output deploy-output.json --config deploy-config.json \
  --base-genesis genesis-base.json --out genesis.json --rollup-out rollup.json \
  --preset defi
```

- **재개**: tokamak-deployer 는 `--resume` 이 없다. `isResume` 분기(`trh-sdk/deploy_contracts.go:145-170`)가 같은 커맨드를 재호출한다 — pending nonce 에 걸린 TX 만 정리되면 idempotent 하게 이어간다.
- **산출물**: `deploy-output.json` (주소 + `l1ChainId`/`l2ChainId` 메타, 스키마는 `types.go:6-23`), `genesis.json`, `rollup.json`
- **플래그**: `--gas-price` (wei) / `--gas-price-multiplier` (percent, 기본 200) / `--gas-price-floor` / `--gas-price-ceil`, env fallback `TOKAMAK_DEPLOY_GAS_PRICE`

### 3.3 입출력 호환성

`deploy-output.json` 은 Foundry `deployments/<chainId>-deploy.json` 과 동일한 **주소 네임스페이스**를 보존한다. 차이는 신규에 `l1ChainId`/`l2ChainId` 메타가 추가된 것뿐이며, L2Genesis.s.sol 은 주소 외 키를 거부하므로 `genesis_prep.go:67 writeAddressesOnly()` 가 메타를 strip 해서 staged 파일을 만든다. 기존 경로로 배포한 체인을 신규 경로의 L2Genesis 단계에 그대로 넘기는 것도 동일한 staging 만 거치면 가능하다.

## 4. 딥다이브 (라인 단위)

### 4.1 진입점

- **기존**: `Deploy.s.sol:285 run()` → `_run()` (321) → `setupSuperchain()` (349) + `setupOpChain()` (371). `setupOpChain` 은 `deployProxies` (399) → `deployImplementations` (422) → `initializeImplementations` (447) 3 단계 함수 호출. 모든 함수가 `broadcast` modifier 를 달고 있어 `vm.startBroadcast()`-`vm.stopBroadcast()` 사이에서 실행되며, `cfg.reuseDeployment()` / `cfg.useFaultProofs()` / `cfg.usePlasma()` 분기를 내부에 갖는다.
- **신규**: `contracts.go:206 Deploy(ctx, cfg, artifactsFS)` — 한 함수 안에서 dial → pending nonce 조회 → `resolveGasPrice` → 26 step 직선 코드 → `if cfg.EnableFaultProof { 6 step 추가 }`. 분기는 Go `if` 하나뿐이다.

### 4.2 컨트랙트 배포 순서

두 방식 모두 **proxy-impl-upgrade 삼각형**을 컨트랙트마다 반복하지만, 배치 방식이 다르다.

- **기존**: `deployProxies()` 에서 모든 프록시를 먼저 배포 → `deployImplementations()` 에서 모든 impl 을 배포 → `initializeImplementations()` 에서 일괄 초기화. 배치 안에서 `create2` + `IMPL_SALT` 로 결정론적 주소.
- **신규**: 컨트랙트 하나씩 (proxy → impl → upgrade) 삼각형을 26회 반복. create2 아님 — 매 배포마다 랜덤 주소. Step 1-5 가 AddressManager/ProxyAdmin/SuperchainConfig 기초 설정, 6-26 이 코어 컨트랙트 6종 삼각형, 27-32 는 fault-proof 시 DisputeGameFactory + AnchorStateRegistry.

동적 step 카운터 구현(`contracts.go:248-267`):
```go
const (baseStepCount = 26; faultProofSteps = 6)
totalSteps := baseStepCount; if cfg.EnableFaultProof { totalSteps += faultProofSteps }
logStep := func(format string, args ...interface{}) {
    stepIdx++
    log.Printf("[deployer] Step %d/%d: %s", stepIdx, totalSteps, fmt.Sprintf(format, args...))
}
```
→ 스텝을 추가/삭제할 때 모든 라벨을 수동 수정할 필요가 사라진다.

### 4.3 가스 가격 전략

- **기존** (`start-deploy.sh:329-334`): `if [[ -n "$GAS_PRICE" && "$GAS_PRICE" -gt 0 ]]; then forge ... --with-gas-price $GAS_PRICE; else forge ...; fi`. env 에 `GAS_PRICE` 를 세팅했을 때만 고정, 아니면 forge 자동 산정.
- **신규** (`gasprice.go:36-87 resolveGasPrice`):
  1. `FixedGasPrice` 있으면 그대로 사용 (forge 의 `--with-gas-price` 패턴 재현)
  2. 없으면 `SuggestGasPrice × multiplier/100` 계산 (기본 200 = 2×)
  3. `[floor=1 Gwei, ceil=100 Gwei]` 로 clamp
  4. 시작 시 1회만 로그 남기고, 반환값을 `Deploy()` 전체 호출 체인에 전달
- trh-sdk 는 `deploy_contracts.go:303-309` 에서 `SuggestGasPrice × 2` 를 계산해 `--gas-price` 로 넘긴다. 즉 실행 중 한 번도 `SuggestGasPrice` 를 호출하지 않는다.

### 4.4 재시도 / 스턱 TX 복구

- **기존**: forge 의 `--resume` + `--fork-retries 10 --fork-retry-backoff 3000` (trh-sdk patch6 로 주입). TX 레벨 교체(같은 nonce + bumped gas) 로직은 없음 — 스턱되면 프로세스가 걸리거나 전체 재실행.
- **신규** (`contracts.go:47-111 sendAndWaitMined`): 모든 deploy/call 이 공통으로 이 헬퍼를 통한다.
  - attempt 1: `initialGasPrice` 로 sign+send, 180 s 대기 (`sendAttemptTimeout`)
  - timeout 시 attempt 2+: `max(previous × 1.25, 현재 SuggestGasPrice)` 로 bump, **동일 nonce 로 replacement** 브로드캐스트
  - `underpriced` 또는 `already known` 에러는 fatal 아닌 retry 신호로 취급
  - 최대 `sendMaxAttempts = 3` (최악 9분 대기 후 fail)
  - 실패 시 마지막 hash 를 에러에 포함 — 재실행 전에 mempool 정리 여부를 운영자가 확인 가능

### 4.5 로깅

- **기존**: forge `console.log(...)` + stdout. 단계 구분은 "Deploying proxies" / "Deploying implementations" 수준의 메시지뿐이며, 개별 컨트랙트 tx hash 가 누락되는 경우가 있다.
- **신규**: `[deployer]` prefix 로 필터링 용이. 단계별 진입 라인, broadcast 시 hash + nonce + bytes, mined 시 block number + status, 배포된 address, ✓/✗ emoji. 파이프(`| tee`)로 흘릴 때 reader 가 죽으면 로그가 통째로 증발하는 이슈가 있어 **직접 파일 리다이렉트**(`> deploy.log 2>&1`) 가 권장된다 (README:225 참고).

### 4.6 아티팩트 전달

- **기존**: `forge-artifacts/` 가 파일 시스템에 존재해야 함. 런타임 forge 빌드 필수.
- **신규** (`assets.go:9-10`):
  ```go
  //go:embed deploy-artifacts
  var DeployArtifactsFS embed.FS
  ```
  `scripts/extract-artifacts.sh` 가 **17 개 컨트랙트 JSON** 을 `forge-artifacts/` 에서 복사해 넣고 (`AddressManager`, `L1CrossDomainMessenger`, `L1ERC721Bridge`, `L1StandardBridge`, `L2OutputOracle`, `OptimismMintableERC20Factory`, `OptimismPortal`, `OptimismPortal2`, `ProxyAdmin`, `SystemConfig`, `SuperchainConfig`, `L1Block`, `DisputeGameFactory`, `AnchorStateRegistry`, `MIPS`, `PreimageOracle`, `Proxy`), `go build` 가 바이너리에 go:embed 로 고정한다. 릴리스 바이너리는 self-contained.

### 4.7 호출자 레이어 (trh-sdk)

- **기존** (`df52538^` 시점, 1265 라인 `deploy_contracts.go`):
  1. `cloneSourcecode` (145 라인 근방): `git clone https://github.com/tokamak-network/tokamak-thanos.git`
  2. `patchStartDeployScript` (720 라인 근방): 알려진 빌드 이슈 7종 패치 — `make submodules` → shallow + non-recursive, `--rpc-url` 제거(L2Genesis), forge 스크립트에 `--fork-retries 10 --fork-retry-backoff 3000` 추가 등
  3. `bash start-deploy.sh build` — 의존성/cannon/op-node/forge/ts 전체 빌드
  4. `bash start-deploy.sh deploy -e .env -c deploy-config.json`
  5. `bash start-deploy.sh generate -e .env -c deploy-config.json`

- **신규** (`deploy_contracts.go` 522 라인 + `deployer_binary.go` 231 라인 + `genesis_prep.go` 178 라인):
  1. `ensureTokamakDeployer` (`deployer_binary.go:33`): `~/.trh/bin/tokamak-deployer-v0.0.5` 캐시 체크 → GitHub Releases 에서 platform-specific tar.gz 다운로드 → 바이너리 추출 → chmod 0755
  2. `SuggestGasPrice × 2` 계산 (`deploy_contracts.go:303-312`) — 현재 suggested 를 2 배로 만들어 tokamak-deployer 에 전달
  3. `runDeployContracts` (`deployer_binary.go:172`): `exec.CommandContext(binaryPath, "deploy-contracts", "--l1-rpc", ..., "--gas-price", ...)`, stdout 을 `t.output` 에 파이프
  4. `prepareL2GenesisInputs` (`genesis_prep.go:40`): deploy-output 에서 메타 strip → `contracts-bedrock/deployments/<l2ChainID>-addresses.json`, deploy-config 복사 → `contracts-bedrock/deploy-config/<l2ChainID>.json` (forge FFI 샌드박스 우회)
  5. `runForgeL2GenesisScript` (`genesis_prep.go:115`): `cmd.Dir = contracts-bedrock; forge script L2Genesis.s.sol:L2Genesis --rpc-url <L1>` → `state-dump-<l2ChainID>.json`
  6. `ensureOpNodeBinary` (`genesis_prep.go:157`): `op-node/bin/op-node` 없으면 `go build -o ./bin/op-node ./cmd` 온디맨드
  7. `runGenerateGenesis` (`deployer_binary.go:187`): `tokamak-deployer generate-genesis --deploy-output ... --config ... --l1-rpc ... --l2-allocs state-dump-*.json --op-node-bin ...`
  8. `maybeInjectDRB` + `maybeFundDRBRegulars` (`deploy_contracts.go:443-450`): gaming/full preset 에서 DRB 레귤러 오퍼레이터 펀딩
  9. `DeployContractState.Status = Completed` persist (`deploy_contracts.go:456-460` — `df52538` 에서 실수로 빠뜨렸다가 `088575a` 에서 복구된 이력)

**fault-proof 시에만** repo clone 이 남는다(`deploy_contracts.go:224-258`): cannon prestate hash 빌드 + `AnchorStateRegistry.sol` 패치 + Sepolia address.json 의 AnchorStateRegistry 를 zero address 로 리셋. 신규 경로에서 clone 이 완전히 사라지지 않은 유일한 이유다.

### 4.8 L2 Genesis 경로 (공통점과 차이)

**공통**: 최종 genesis.json/rollup.json 은 둘 다 `op-node genesis l2` 가 만든다. 입력(`--deploy-config`/`--l1-deployments`/`--l2-allocs`)도 동일.

**차이**: 기존은 op-node 출력을 그대로 반환. 신규는 `generator.go:43-126 Generate()` 가 op-node 출력을 받아 5-step 후처리를 수행:
1. DRB inject — `preset in {gaming, full}` 일 때만 (`drb.go`)
2. USDC inject — `alloc` 에 USDC 컨트랙트 바이트코드 + storage 주입 (`usdc.go`, 188 라인)
3. MultiTokenPaymaster inject — AA paymaster 바이트코드 (`paymaster.go`)
4. L1Block Isthmus patch — `predeployToCodeNamespace(0x...4015)` 계산 후 `code` 필드만 교체, balance/storage/nonce 보존 (`l1block.go:40-120`)
5. Rollup hash update — alloc 패치 후 `genesis.l2.hash` 재계산해서 rollup.json 갱신 (`rollup.go`)

기존 경로에서는 이 후처리가 trh-sdk 별도 파일(`artifacts_download.go`, bytecode 상수 등)에 분산돼 있었고, `df52538` 에서 deployer 측으로 통합됐다.

### 4.9 CI / 릴리스

- **기존**: tokamak-thanos 릴리스 없이 SHA 기반. trh-sdk 는 원하는 브랜치를 clone.
- **신규**: `.github/workflows/release-deployer.yml` + goreleaser. 태그 포맷 `tokamak-deployer/vX.Y.Z` (monorepo path-separated, `2026-04-17` 커밋 `b845514` 에서 결정). 산출물: `darwin-amd64`, `darwin-arm64`, `linux-amd64`, `linux-arm64` + `checksums.txt`. trh-sdk 는 `TokamakDeployerVersion` 상수 한 줄 변경으로 전역 업그레이드.

## 5. 의사결정 요약

| 관점 | 얻은 것 | 포기한 것 |
|---|---|---|
| 속도 | 빌드 체인 제거 (~20-25분 절감) | — |
| 신뢰성 | nonce-level replacement TX, 고정 가스, pinned 버전 | forge 의 `--resume` 복원 편의 |
| 관측성 | step-level + tx-level 로그 | — |
| 재사용성 | 단일 바이너리 배포, CI 에서 쉽게 핀 | Solidity level `cfg.reuseDeployment()` — 기 배포 impl 재사용 불가 (매번 신규 배포) |
| 확장성 | deploy 스텝 추가가 Go if 문 한 줄 | Solidity level 의 `usePlasma()` / 고급 분기 (ProtocolVersions, DelayedWETH 풀셋 등은 아직 미지원) |

**여전히 forge 가 필요한 곳**:
- L2Genesis.s.sol (state-dump 생성) — 현재 시점에 Go 이관 없음
- fault-proof 가 ON 일 때 cannon prestate 빌드 + AnchorStateRegistry 패치 (Solidity 수정 필요)
- fault-proof 관련 initialize / setImplementation / Safe wallet 실행 (Deploy.s.sol 의 해당 함수들이 그대로 재사용됨)

**주력 경로(Preset)의 실제 구성**: `trh-backend/preset_deploy.go:127 EnableFaultProof:true` 때문에 tokamak-deployer 가 proxy+upgrade 까지만 처리하고, 나머지 initialize/setImplementation 단계는 trh-sdk 가 clone 후 forge 로 실행하는 **2단계 하이브리드**. 순수 Go 전환은 fault-proof 완전 포팅(섹션 6-2) 이 완료되어야 가능.

## 6. 향후 후보

1. **L2Genesis Go 이관** — forge FFI 샌드박스와 prepareL2GenesisInputs staging 자체를 제거 가능
2. **Fault-proof 완전 포팅** — 현재는 **DisputeGameFactoryProxy + AnchorStateRegistryProxy 의 deploy + plain upgrade 만** 커버 (`contracts.go:525-584`). 나머지는 전부 forge 경로에 남아있어 Preset 경로(fault-proof ON 하드코딩)는 여전히 clone+빌드를 요구함. 완전 포팅을 위해 필요한 것:
   - `initializeDisputeGameFactory` / `initializeDelayedWETH` / `initializePermissionedDelayedWETH` (`Deploy.s.sol:1030/1066/1119`) — 전부 `_upgradeAndCallViaSafe` (240-248) 경유 → **GnosisSafe `execTransaction` 서명 포맷 Go 포팅** 이 최대 장애물
   - `setAlphabetFaultGameImplementation` / `setFastFaultGameImplementation` / `setCannonFaultGameImplementation` / `setPermissionedCannonFaultGameImplementation` 4종 (389-392)
   - `deployProtocolVersions` + `initializeProtocolVersions` (816, 1735)
   - `transferDisputeGameFactoryOwnership` / `transferDelayedWETHOwnership` (394-395)
   - **Cannon prestate 는 Go 포팅 불가에 가까움** — MIPS + forge submodules + Rust 빌드 필요. 이 단계만은 외부 빌드 또는 사전 빌드된 해시 주입으로 우회해야 함
   - **AnchorStateRegistry 소스 패치** (`setInitialAnchorState` 추가) — `trh-sdk/deploy_contracts.go:485-522` 가 하는 clone+수정+재컴파일을 대체하려면 해당 함수를 upstream 에 병합하거나 deploy-time 바이트코드 패치로 대체 필요
3. ~~**`reuseDeployment` 복구**~~ ✅ **완료 (v0.0.9, 2026-05-07)** — `--reuse-deployment` / `--reuse-impls` / `--reuse-strict` CLI 추가, 9개 Proxy-backed impl(SuperchainConfig, OptimismPortal, SystemConfig, L1StandardBridge, L1CrossDomainMessenger, OptimismMintableERC20Factory, L1ERC721Bridge, L2OutputOracle, DisputeGameFactory) 의 재사용 지원. 자세히는 §7 참조. **`IMPL_SALT` (CREATE2)** 는 별도 후보로 남음 — fallback 신규 배포는 여전히 random-CREATE
4. **병렬 nonce 구간** — 현재 완전 순차. 초기화 단계(step 5+8+11 등) 는 서로 독립적 → 제한적 병렬화 가능
5. **L1 `initialize()` 호출 복원** — 현재 `contracts.go:202` 가 명시하듯 *"Try upgrade() first (simpler, no initialization)"* 로 plain `upgrade()` 만 수행. Foundry 경로의 `_upgradeAndCallViaSafe` 가 넣던 `initialize` 파라미터(Guardian / Challenger / Gas limit / SystemConfig 설정 등) 가 어디서 들어가는지 현재 문서화되지 않음. Safe 없이 `ProxyAdmin.upgradeToAndCall` 로 축소 포팅하면 5번을 먼저 끝낸 뒤 2번(fault-proof) 포팅이 쉬워짐

## 부록 A — 산출물 스키마

**`deploy-output.json`** (신규, `internal/deployer/types.go:6-23`):
```json
{
  "l1ChainId": 11155111, "l2ChainId": 111551143645,
  "AddressManager": "0x...", "ProxyAdmin": "0x...",
  "SuperchainConfigProxy": "0x...", "OptimismPortalProxy": "0x...",
  "SystemConfigProxy": "0x...", "L1StandardBridgeProxy": "0x...",
  "L1CrossDomainMessengerProxy": "0x...", "OptimismMintableERC20FactoryProxy": "0x...",
  "L1ERC721BridgeProxy": "0x...", "L2OutputOracleProxy": "0x...",
  "DisputeGameFactoryProxy": "0x...",   // fault-proof only
  "AnchorStateRegistryProxy": "0x..."   // fault-proof only
}
```

**기존 `<chainId>-deploy.json`** (Foundry `hardhat-deploy` 스타일): 주소 필드는 같지만 `l1ChainId`/`l2ChainId` 메타가 없으며, 대신 `SafeProxyFactory`/`SafeSingleton`/`SystemOwnerSafe` 등 SafeWallet 관련 항목과 DelayedWETH/PermissionedDelayedWETH 등 fault-proof 추가 항목이 포함된다.

## 부록 B — 파일 레퍼런스

| 주제 | 파일 | 핵심 위치 |
|---|---|---|
| 기존 L1 진입점 | `packages/tokamak/contracts-bedrock/scripts/Deploy.s.sol` | `:285 run()`, `:320 _run()`, `:349 setupSuperchain()`, `:371 setupOpChain()` |
| 기존 L2 genesis | `packages/tokamak/contracts-bedrock/scripts/L2Genesis.s.sol` | `:127 run()`, `:137 runWithOptions()`, `:188 setPredeployProxies()` |
| 기존 셸 래퍼 | `packages/tokamak/contracts-bedrock/scripts/start-deploy.sh` | `:320 deployContracts`, `:348 resumeDeployContracts`, `:374 generateL2Genesis` |
| 기존 호출자 | `trh-sdk/pkg/stacks/thanos/deploy_contracts.go` @ df52538^ | `:145 cloneSourcecode`, `:720 patchStartDeployScript`, `:689 redeploy`, `:699 deploy`, `:503 generate` |
| 신규 CLI | `cmd/tokamak-deployer/cmd/{root,deploy_contracts,generate_genesis,assets}.go` | `deploy_contracts.go:26 deployContractsCmd`, `generate_genesis.go:20 generateGenesisCmd`, `assets.go:9 //go:embed` |
| 신규 L1 deploy loop | `cmd/tokamak-deployer/internal/deployer/contracts.go` | `:47 sendAndWaitMined`, `:132 deployRawContract`, `:196 setProxyType`, `:201 upgradeProxyViaAdmin`, `:206 Deploy` |
| 신규 가스 | `cmd/tokamak-deployer/internal/deployer/gasprice.go` | `:36 resolveGasPrice`, `:13 defaults` |
| 신규 genesis | `cmd/tokamak-deployer/internal/genesis/generator.go` | `:43 Generate`, 5 post-steps |
| 신규 호출자 | `trh-sdk/pkg/stacks/thanos/deployer_binary.go` | `:22 TokamakDeployerVersion`, `:33 ensureTokamakDeployer`, `:172 runDeployContracts`, `:187 runGenerateGenesis` |
| 신규 호출자 보조 | `trh-sdk/pkg/stacks/thanos/genesis_prep.go` | `:40 prepareL2GenesisInputs`, `:67 writeAddressesOnly`, `:115 runForgeL2GenesisScript`, `:157 ensureOpNodeBinary` |
| 전환 커밋 | trh-sdk | `df52538` (2026-04-16, L1 경로 교체), `8bd3fea` (2026-04-16, L2 Genesis 오케스트레이션), `230cdb8` (2026-04-17, v0.0.5 고정 가스) |

## 7. Reuse 기능 도입 (v0.0.9, 2026-05-07)

### 7.1 무엇이 추가됐나

신규 CLI 플래그 3종 (`tokamak-deployer/cmd/deploy_contracts.go`):

| 플래그 | 기본값 | 동작 |
|---|---|---|
| `--reuse-deployment` | `false` | 마스터 토글. on 일 때만 registry 검사 + 재사용 시도 |
| `--reuse-impls <path>` | (없음) | embedded registry 를 외부 JSON 으로 override |
| `--reuse-strict` | `false` | preflight 실패 시 즉시 abort. off 면 silent fallback to fresh deploy |

**대상**: Proxy 뒤 implementation 9개 — SuperchainConfig, OptimismPortal, SystemConfig, L1StandardBridge, L1CrossDomainMessenger, OptimismMintableERC20Factory, L1ERC721Bridge, L2OutputOracle, DisputeGameFactory.

**제외**: AddressManager / ProxyAdmin (per-chain 소유권), 모든 Proxy (체인별 신규), AnchorStateRegistry / DelayedWETH (constructor 인자가 chain-specific).

### 7.2 검증 메커니즘

`Deploy()` 진입 직후 preflight 실행 (`internal/deployer/reuse.go:Registry.verify`):
1. registry 의 각 entry 에 대해 `eth_getCode(addr)` → on-chain runtime bytecode 획득
2. binary 의 embedded `deployedBytecode.object` 와 keccak256 비교
3. 일치 → reuseTable 에 등록 / 불일치 → silent skip (또는 strict 시 abort)

**핵심 가정**: 9개 reuse 대상 모두 constructor 인자 없는 impl → immutable byte 영역 없음 → byte-for-byte equality 가 정확. (`AnchorStateRegistry` 는 DGF proxy 인자, `DelayedWETH` 는 delay 인자 받기 때문에 reuse 불가 → 후보에서 제외.)

### 7.3 Registry 형식과 위치

Embedded: `cmd/tokamak-deployer/cmd/registry/{l1ChainId}.json`

```json
{
  "tokamakDeployerVersion": "v0.0.9",
  "l1ChainId": 11155111,
  "comment": "...",
  "implementations": {
    "SuperchainConfig":             "0x...",
    "OptimismPortal":               "0x...",
    ...
  }
}
```

`tokamakDeployerVersion` 은 informational (로그 출력만), `l1ChainId` 는 runtime client.ChainID() 와 일치해야 함 (불일치 = fatal). `implementations` 키 9개 중 일부만 있어도 동작.

CLI override: `--reuse-impls <path>` 가 embedded 보다 우선.

### 7.4 trh-sdk 측 wiring

`trh-sdk/pkg/stacks/thanos/deployer_binary.go` (`3b96c4d`):
- `TokamakDeployerVersion` v0.0.8 → **v0.0.9**
- `deployContractsOpts.ReuseDeployment bool` + `RegistryPath string` 추가
- `buildDeployContractsArgs` 가 `ReuseDeployment` 시 `--reuse-deployment` 전달; 추가로 `RegistryPath` 가 같이 set 되면 `--reuse-impls <path>` 도 전달
- 기존 `trh-sdk --reuse-deployment` CLI 플래그가 이제 **양쪽 경로(Foundry + Go) 동시 활성화**. 이전엔 Foundry 만 영향

### 7.5 성능 효과

이론치: 9 step × 10-30s = **약 1.5-4.5 분** Sepolia deploy 시간 단축. `tokamak-deployer-gas-price` 의 5m47s 베이스라인 → ~3m45s 예상.

실측 (anvil 로컬): nonce delta = `26 base steps - 8 reused (no fault-proof) = 18` 정확히 일치, L2OutputOracle impl 주소가 두 deploy 간 동일.

### 7.6 Sepolia seeding (v0.0.10)

**v0.0.9 제약 (해소됨)**: 초기 v0.0.9 발행 시점에 Foundry-era `packages/tokamak/contracts-bedrock/deployments/thanos-stack-sepolia/address.json` 의 9개 impl 모두 v0.0.9 embedded artifact 와 **bytecode 미일치** (검증: SystemConfig 포함 9개 모두 selector 개수가 다름; 같은 solc 0.8.15 trailer 이지만 source revision 차이로 코드가 ~24-39% 더 큼). 따라서 v0.0.9 의 Sepolia registry 는 `implementations: {}` 빈 상태로 발행됨.

**v0.0.10 해결**: 2026-05-07 에 v0.0.9 binary 로 Sepolia 신규 fault-proof 배포(`chainId=111551149999`, deployer `0x7220c7…499c`, 35 steps, ~7m, 0.024 ETH) 를 실행. 결과 `deploy-output.json:implementations` 9개 주소 모두 `cast code + keccak256` 으로 v0.0.9 artifact 와 **9/9 MATCH** 검증 후 `cmd/registry/11155111.json` 에 등록 (`c0c6ec5a0f`). v0.0.10 binary 가 이 populated registry 를 동봉. 실측 v0.0.10 binary 의 Sepolia preflight 로그: `Reuse preflight: 9/9 implementations reusable`.

**현재 상태**: trh-sdk v0.0.10 + `trh-sdk deploy-contracts --reuse-deployment` → Sepolia 에서 9개 impl 재사용 자동 활성화, 추가 설정 불필요.

다른 L1 chainId (Mainnet 1, 사설 testnet 등) 등록 절차는 `tokamak-thanos/cmd/tokamak-deployer/cmd/registry/README.md` 참고.

### 7.7 커밋 레퍼런스

| Repo | Commit / Tag | 내용 |
|---|---|---|
| tokamak-thanos | `68515b36ca` | tokamak-deployer reuse 기능 13-task 구현 |
| tokamak-thanos | tag `tokamak-deployer/v0.0.9` | goreleaser 4 platform binaries 발행 (Sepolia registry 빈 상태) |
| tokamak-thanos | `a063b10675` | Sepolia registry comment + README 갱신 (호환성 가이드) |
| tokamak-thanos | `c0c6ec5a0f` | Sepolia registry 9 impl 등록 (fresh v0.0.9 deploy 결과) |
| tokamak-thanos | tag `tokamak-deployer/v0.0.10` | populated Sepolia registry 동봉 binaries 발행 |
| trh-sdk | `3b96c4d` | wiring + version bump v0.0.8 → v0.0.9 + 4 unit tests |
| trh-sdk | `e57a915` | TokamakDeployerVersion v0.0.9 → v0.0.10 (populated Sepolia registry 활성) |

### 7.8 후속 후보

- **`IMPL_SALT` / CREATE2** — 본 변경에서 미포함. fallback 신규 배포에 deterministic 주소 도입하면 IMPL_SALT 환경변수로 멀티-체인 주소 일관성 확보 가능 (§6 의 별도 항목)
- ~~**trh-sdk 에 `--reuse-impls <path>` CLI 플래그 추가**~~ ✅ **완료 (trh-sdk `21d6a3e`, 2026-05-07)** — `flags.ReuseImplsFlag` (StringFlag, env `TRH_SDK_REUSE_IMPLS`) → `DeployContractsInput.RegistryPath` → `deployContractsOpts.RegistryPath`. 사용자가 `trh-sdk deploy-contracts --reuse-deployment --reuse-impls /path/to/x.json` 으로 embedded registry override 가능
- **Mainnet registry 등록** — Sepolia 절차 그대로. 첫 mainnet 배포 후 `deploy-output.json:implementations` 를 `registry/1.json` 으로 PR
- **AnchorStateRegistry / DelayedWETH 의 constructor-aware reuse** — chain-specific 인자가 같은 경우에만 reuse 허용. Foundry 의 `delayedWETH.delay()` view check 패턴 참고

## 관련 문서

- [[thanos-deployer-analysis]] — 기존 경로 전체 8-레이어 아키텍처 분석
- [[tokamak-deployer-logging]] — 신규 경로 로깅 상세
- [[tokamak-deployer-gas-price]] — v0.0.5 고정 가스 전략 근거 + Sepolia 측정 결과
- [[l2-deployment]] — L2 배포 파이프라인 전체 개요
- [[drb-local-compose-path-template-bugs]] — 이 전환 과정에서 드러난 5 개 경로·템플릿 버그 (2026-04-17)
