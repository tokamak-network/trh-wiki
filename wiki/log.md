# Wiki Log

Append-only chronological record of all wiki operations.

Parse the last 5 entries: `grep "^## \[" wiki/log.md | tail -5`

---

## [2026-04-27] new | DisputeGameFactory no implementations (Bug #8 pre-v0.0.6) + StorageSetter bytecode fix

Pages added:
  [[troubleshooting/dispute-game-factory-no-implementations-pre-v006]] — root cause, affected stacks, fix options

Key facts captured:
  - tokamak-deployer < v0.0.6 silently skipped fault proof steps 27-32 without --fault-proof flag
  - Affected stacks have DisputeGameFactory with zero game implementations → op-proposer execution reverted
  - Confirmed in stack 7640669c: deploy-output.json missing FaultDisputeGame/MIPS/PreimageOracle
  - storageSetterBytecode was 14 bytes short (955→969): two dispatcher stubs missing at offset 0x191, causing InvalidJump
  - originalImpl EIP-1967 fallback added: reads impl from proxy storage slot when deploy-output.json omits it
  - trh-sdk commit e396bb1 fixes both bytecode and EIP-1967 fallback

---

## [2026-04-27] new | op-node genesis l1=0 pitfall — SystemConfig.startBlock() uninitialized by Go deployer

Pages added:
  [[troubleshooting/op-node-genesis-l1-block-zero]] — root cause, fix (cmd.go patch), redeploy procedure

Key facts captured:
  - Go deployer uses upgradeProxyViaAdmin (no initialize()), so SystemConfig.startBlock() = 0
  - Fix: read L1StartingBlockTag from deploy-config.json instead
  - Commit 1e5426d6b8 on tokamak-thanos main removes systemconfig.go, patches cmd.go
  - Redeploy requires: wipe geth chaindata → geth init → restart all services
  - op-geth image requires --entrypoint geth for geth init (CMD form fails)

---

## [2026-04-20] new | trh-sdk — AnchorStateRegistry setInitialAnchorState 누락 (RC3) StorageSetter fallback

New page: [[anchor-state-registry-missing-set-initial-anchor-state]] (troubleshooting/)

변경 요약:
  - RC3 근본 원인: tokamak-deployer embedded 바이트코드에 setInitialAnchorState 없음
    → patchAnchorStateRegistry()는 .sol만 패치; deployed impl에 효과 없음
  - 수정: Guard B 실패 시 bootstrapAnchorStateViaStorageSetter() 자동 호출
  - StorageSetter 배포 → upgradeAndCall → storage 검증 → impl 복원 (loud-fail)
  - trh-sdk commit: 339c882

관련 파일:
  - pkg/stacks/thanos/deploy_chain.go (bootstrapAnchorStateViaStorageSetter 추가)
  - pkg/stacks/thanos/local_network.go (콜사이트 업데이트)

---

## [2026-04-19] new | trh-sdk — Gaming/Full preset genesis hash mismatch (RC1) 수정 문서화

New page: [[gaming-full-preset-genesis-hash-mismatch]] (troubleshooting/)

변경 요약:
  - RC1 근본 원인: maybeInjectDRB/maybeFundDRBRegulars가 runGenerateGenesis 이후 genesis.json 수정
    → rollup.json의 genesis.l2.hash가 stale → op-node genesis hash mismatch crash
  - 수정: drb preset에서 두 번째 generate-genesis 호출 (--base-genesis로 post-DRB genesis 재해싱)
  - USDC/MTP/L1Block post-processing 모두 idempotent 확인
  - trh-sdk commit: 323489c

관련 파일:
  - `trh-sdk/pkg/stacks/thanos/deploy_contracts.go` (RC1 fix)

---

## [2026-04-19] update | cross-trade — CRT E2E 런 루트 원인 3건 수정 문서화

Updated page: [[cross-trade]] (components/integration/)
Source: CRT-01~10 + CT-E2E-01~05 전체 실행 (2026-04-18~19)

변경 요약:
  - E2E 결과 테이블 업데이트: CRT-08~10 ✅ PASS, CT-E2E-01~05 ✅ 완료
  - 새 섹션 "루트 원인 수정 (2026-04-19 CRT E2E 런)" 추가 — 3건:
    1. **Fix 1: L1CrossDomainMessengerProxy.initialize() 미호출 (CDM portal=0x0)**
       tokamak-deployer가 upgrade()만 호출하고 initialize()를 생략 → portal 슬롯 = 0x0 → CRT-02 실패.
       trh-sdk deploy_chain.go에 initL1CrossDomainMessenger() 추가 (멱등성 가드 + pre-flight eth_call + 100바이트 ABI 수동 인코딩).
    2. **Fix 2: L2CDM predeploy 오주입**
       cross_trade_local.go가 initialize() 파라미터에 L1CDM 주소를 L2CDM으로 전달. 0x4200...0007 상수로 교체.
    3. **Fix 3: L1UsdcBridgeAdapter — selector 불일치**
       Circle L1UsdcBridge는 bridgeERC20To가 아닌 depositERC20To를 노출 → CRT-09 revert.
       L1UsdcBridgeAdapter.sol 신규 작성 + trh-backend RegisterCrossTradeL2()에서 프로그래매틱 배포.

관련 파일:
  - `trh-sdk/pkg/stacks/thanos/deploy_chain.go` (initL1CrossDomainMessenger 신규)
  - `trh-sdk/pkg/stacks/thanos/local_network.go` (CDM init 호출 추가)
  - `trh-sdk/pkg/stacks/thanos/cross_trade_local.go` (L2CDM predeploy 상수 교체)
  - `crossTrade/contracts/L1/L1UsdcBridgeAdapter.sol` (신규 어댑터)
  - `trh-backend/pkg/services/thanos/integrations/cross_trade_local.go` (deployL1UsdcBridgeAdapter + 조건부 배포)

## [2026-04-18] add | forge-l2genesis-silent-slow — forge L2Genesis 단계 로그 무음·과도 지연 원인과 픽스

New page: [[forge-l2genesis-silent-slow]] (troubleshooting/)
Source: 로컬 L2 배포 중 `✅ All contracts deployed successfully!` 이후 진행 피드백 무음 + 수분간 대기

변경 요약:
  - 증상 3개를 한 곳에 정리: (a) 로그가 `state-dumpdir/...addresses/...config/...`처럼
    경로가 구분자 없이 이어붙어 보임, (b) forge 실행 동안 수분간 무음, (c) 체감상 필요 이상으로 오래 걸림.
  - 근본 원인 3개 식별:
    1. `zap.SugaredLogger.Info(msg, k, v, ...)` 오용 — `fmt.Sprint` 방식이라 전부 이어붙음. 구조화 kv는 `Infow`를 써야 함.
    2. `cmd.CombinedOutput()` — 프로세스 종료까지 차단·침묵, 실패 시에만 덤프.
    3. 불필요한 `--rpc-url` — L2Genesis.s.sol은 `vm.etch`/`vm.chainId`/`vm.dumpState`만 씀(RPC 미참조).
       upstream `contracts-bedrock/package.json`의 `genesis` 스크립트도 RPC 없이 호출(`run()` = `runWithStateDump()` 별칭).
  - 픽스: `Info` → `Infow` 전환, `CombinedOutput` → `StdoutPipe`/`StderrPipe` 라인 스캐너(`[forge]` 프리픽스),
    `--rpc-url` 제거 + 호출부 `l1RPCURL` 인자 제거.
  - 트레이드오프 명시: 현재 스트리밍은 PTY가 아니라 pipe라 forge가 `isatty` 검사 후 block-buffered로
    내려갈 수 있음(RPC 제거 속도 이득과는 별개). 필요 시 `ExecuteCommandStreamInDir`에 env 지원을 얹어
    PTY 경로로 이행하는 것이 다음 스텝.

관련 파일:
  - `trh-sdk/pkg/stacks/thanos/genesis_prep.go` (runForgeL2GenesisScript, ensureOpNodeBinary)
  - `trh-sdk/pkg/stacks/thanos/deploy_contracts.go` (runForgeL2GenesisScript 호출부)

검증:
  - `go build ./pkg/stacks/thanos/...` pass
  - `go vet ./pkg/stacks/thanos/...` clean
  - `pkg/stacks/thanos` unit tests pass
  - 실제 로컬 L2 배포로 런타임 검증은 다음 세션 예정

## [2026-04-18] update | cross-trade — USDC TokenPair 주소 확정, Thanos UI guidance, USDC E2E 테스트 추가

Updated page: [[cross-trade]] (components/integration/)

변경 요약:
  - 지원 토큰 테이블: USDC L1/L2 주소 TBD → 확정값으로 업데이트
    - L1 Sepolia USDC: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
    - L2 predeploy USDC: `0x4200000000000000000000000000000000000778`
    - USDC ERC20 approve 선행 필요 (ETH와 달리 `{ value }` 없음) 명시
  - `deployment.go` `autoInstallCrossTradeLocal()`에서 USDC TokenPair 슬라이스 등록 (2026-04-18 구현)
  - `cross_trade_local.go` `l2l2Tokens` USDC address 픽스: `""` → `0x4200...0778`
  - Thanos 방향 UI 안내 메시지 (해결책 2) 추가: `thanos-direction-notice` data-testid,
    `getAllowedDestinationChains().length === 0` 조건 렌더링
  - E2E 테스트 섹션 재구성: CRT-01~07(완료) + CRT-08~10(USDC, live 대기)
  - 신규 spec 파일 `08-defi-crosstrade-electron.spec.ts` CT-E2E-01~05 표 추가

관련 파일:
  - `trh-backend/pkg/services/thanos/deployment.go` (L755 — TokenPair USDC 등록)
  - `trh-backend/pkg/services/thanos/integrations/cross_trade_local.go` (l2l2Tokens USDC address)
  - `crossTrade/frontend/cross-trade-dapp/src/components/CreateRequest.tsx` (thanos-direction-notice)
  - `tests/e2e/crosstrade-tx.live.spec.ts` (CRT-08~10 추가)
  - `tests/e2e/08-defi-crosstrade-electron.spec.ts` (신규)

## [2026-04-18] update | drb-local-compose-path-template-bugs — Bug #8 consumer gap fixed (readDeploymentContracts path)

Updated page: [[drb-local-compose-path-template-bugs]] (troubleshooting/)
Source: advisor 리뷰로 드러난 producer-consumer 링크 격차

변경 요약:
  - Producer fix 만으로는 불충분함을 발견: tokamak-deployer 는
    `<deploymentPath>/deploy-output.json` 에 쓰지만 consumer
    (`readDeploymentContracts`) 는 `<contracts-bedrock>/deployments/<L1ChainID>-deploy.json` 을 읽음.
  - 후자는 `cloneSourcecode` 가 tokamak-thanos 레포에서 체크아웃하는 forge 시대
    artifact 로, fresh 배포에도 stale 상태로 존재 (10 core addresses, no fault-proof).
    새 파이프라인의 어떤 단계도 재작성하지 않음.
  - trh-sdk `2a688a8`: `readDeploymentContracts` searchPaths 에
    `deploy-output.json` 을 최우선으로 prepend. Bug #7 의 new-path-first 패턴 동일.
  - Bug #8 wiki 섹션 rewrite: 3-layer fix 표 + producer-consumer 격차 설명 +
    caller 범위 주의 추가 (`setupSafeWallet` 은 `SystemOwnerSafe` 필요 → 여전히
    legacy 경로 의존).

검증:
  - trh-sdk unit tests: `TestReadDeploymentContracts_DeployOutputJSON`,
    `TestReadDeploymentContracts_DeployOutputPrecedence`,
    `TestReadDeploymentContracts_FaultProofAddresses` 모두 pass
  - 전체 `pkg/stacks/thanos` 테스트 pass
  - Sepolia 실제 재배포 검증은 별도 세션에서 필요

---

## [2026-04-18] update | drb-local-compose-path-template-bugs — Bug #8 resolved (--fault-proof flag wiring)

Updated page: [[drb-local-compose-path-template-bugs]] (troubleshooting/)
Source: Bug #8 root-cause 재분석 + 양쪽 레이어 수정

변경 요약:
  - 기존 가설 "deploy-output.json emit 누락" 은 틀렸음. 실제 원인은
    tokamak-deployer `deploy-contracts` CLI 에 `--fault-proof` 플래그
    자체가 미등록 → `cfg.EnableFaultProof` 항상 false → steps 27-32 전체 skip.
  - tokamak-thanos `7af425cdf4` 에서 플래그 와이어링 + 단위 테스트
    (deploy_contracts_internal_test.go)
  - tokamak-deployer `v0.0.6` 태그 릴리스 (GH Actions 빌드)
  - trh-sdk `deployContractsOpts.EnableFaultProof` 추가, 두 콜사이트
    (isResume + fresh) 에서 와이어, `TokamakDeployerVersion v0.0.6` bump
  - Bug #8 section root cause/Fix/검증 섹션 전면 재작성

검증 (code-complete, E2E runtime on Sepolia 은 보류):
  - tokamak-thanos: flag 등록 unit test + anvil integration test
    (`TestDeployContracts_FaultProof_Anvil`, 33s) — steps 27-32 가 실제로
    실행되고 `AnchorStateRegistryProxy`/`DisputeGameFactoryProxy` 가
    `deploy-output.json` 에 non-zero 로 기록됨 을 확인
  - trh-sdk: args passing unit test + `readDeploymentContracts` fixture
    test — JSON tag 가 producer output 과 매치
  - 아직 확인 안 된 영역: Sepolia 에서 실제 fault-proof 컨트랙트의 bytecode
    정상성 + on-chain initialization. 별도 fresh 배포 세션 필요.

---

## [2026-04-18] update | drb-local-compose-path-template-bugs — Fix #5/#7 runtime verified + Bug #8 신규 (미해결)

Updated page: [[drb-local-compose-path-template-bugs]] (troubleshooting/)
Source: 2026-04-18 runtime 검증 세션 (trh-backend + docker compose resume-deploy)

실행 환경:
  - trh-backend image digest `sha256:84347f2d...` (2026-04-17 18:54Z build,
    trh-sdk `4c3e33b` 포함)
  - 기존 deployment `5ffe7da8-6bb4-4734-bd5e-6313672286c4`
    (status=FailedToDeploy, preset gaming, feeToken USDT, faultProof ON)
  - Stale volume 상태 준비:
    - `_op-geth-data`: `.genesis-hash=5bf1dbf...` 현재 genesis.json 과 **일치**
    - `_drb-leader-keys/leadernode.bin`: Jan 6 image-layer default key
    - `deploy-config.json` at `<deployPath>/` (new tokamak-deployer path)

Changes:
  - **Fix #7 runtime verified ✅**: resume 시 anchor init 단계까지 도달
    (`local_network.go:163`). 그 전 단계인 `readDeploymentContracts()` →
    `readBedrockDeployConfigTemplate` 가 모두 성공했음을 간접 증명.
  - **Fix #5 runtime verified ✅**: backend 로그의
    `op-geth volume already initialized with matching genesis, skipping init`
    (19:05:52.695Z) 마커가 Fix C 의 새 volume-inspect + marker-read
    로직이 정상 발동함을 직접 증명. 준비된 stale-but-matching volume
    시나리오에서 skip-init branch 선택.
  - **Fix #6b 미도달 ⚠️**: `orchestrateDRBOperators` 진입 전 Bug #8 이
    차단. Fix #6b 는 코드 경로가 advisor-reviewed + Fix #1/#7 와 structurally
    유사하므로 높은 신뢰도. E2E 필수성 낮음.
  - **Bug #8 신규 섹션**: `AnchorStateRegistryProxy address not found in
    deployed contracts` (`local_network.go:163-164`). 근본 원인은 new
    tokamak-deployer 의 `deploy-output.json` 및 Foundry layer 의
    `11155111-deploy.json` 모두 AnchorStateRegistryProxy 필드가 없다는
    것. `deploy-methods-comparison` 에 이미 기록된 "반쪽 포팅" 상태의 결과.
    분류상 Bug #1/#7 과 동급 (new deployer 산출 incomplete) 이나 **fix
    위치가 producer-side (tokamak-deployer upstream)** 이라 consumer
    재매핑으로 해결 불가.
  - 상태 테이블에 Bug #8 행 추가, Fix #5/#7 runtime ✅ 로 갱신.

Tangential discovery (이 버그들과 무관하지만 기록): trh-backend 이미지
자체에 docker CLI 가 베이크되어 있지 않아 `resources/docker-compose.yml`
entrypoint `["./main"]` 만으로 backend 실행 시 orchestration step 에서
`exec: "docker": executable file not found in $PATH` 로 실패. Electron 앱
의 동작 경로에서는 외부에서 CLI 를 주입하는 듯함. 본 검증 세션에서는
`docker exec` 로 런타임 설치해 우회. 별도 이슈로 분리할 필요 있음.

## [2026-04-18] update | drb-local-compose-path-template-bugs — Bug #7 코드 수정 (readBedrockDeployConfigTemplate)

Updated page: [[drb-local-compose-path-template-bugs]] (troubleshooting/)
Source: trh-sdk commit `4c3e33b`

Changes:
  - **Bug #7 상태 "미해결" → "코드 수정, E2E 미확인"**:
    `readBedrockDeployConfigTemplate` (`shutdown.go:304-341`) 가 Bug #1
    동일 패턴 (new path 우선 + legacy fallback) 으로 수정됨. 2026-01-27
    커밋 `191e730` 에서 추가된 "Force use of scripts/deploy-config.json
    as requested" 하드코딩은 Foundry 시대의 의도였고 2026-04-16
    tokamak-deployer 전환 후 이유 소멸 — git blame 으로 확인.
  - **단위 테스트 4개 추가** (`shutdown_test.go`): NewPath /
    LegacyFallback / NewPathPrecedence (new 우선) / NoneFound. 모두 통과.
  - **해결 후보 섹션을 수정 섹션으로 대체**: 채택된 해결책 (후보 1) 의
    실제 코드와 근거 기록.
  - **상태 테이블 업데이트**: Bug #7 칸 코드 수정 완료 + E2E 미확인.

E2E runtime 확인은 아직 미완. trh-backend 가 이 SDK (`4c3e33b`) 로
bump 된 후 DRB gaming + USDT + fault-proof ON resume-deploy 를 재실행해야
함. Fix #5 (op-geth volume stale-check) + Fix #6b (leader PeerID
restart) 의 runtime 경로도 Bug #7 해결 이후 비로소 검증 가능하므로 같은
런으로 확인.

## [2026-04-18] update | drb-local-compose-path-template-bugs — Bug #5/#6 코드 수정 + Bug #7 신규

Updated page: [[drb-local-compose-path-template-bugs]] (troubleshooting/)
Source: 2026-04-18 E2E 재현 세션, trh-sdk commit `0f453c3` + trh-backend commit `f732a48`

Changes:
  - **Bug #5 근본 원인 정정**: 기존 "hash 재초기화 로직이 resume 에서 발동
    안 함" 기술은 증상. 실제 원인은 `os.Stat(<deployPath>/op-geth-data/chaindata)`
    host 파일시스템 probe — op-geth-data 는 **Docker named volume** 이므로
    host 경로는 존재하지 않음. 수정: `docker volume inspect` + alpine
    helper container 로 volume 내부 `.genesis-hash` marker 를 읽고 씀.
  - **Bug #6a workaround 적용**: 이미지 교체 대신 docker-compose 에
    `drb-leader` 서비스 network alias `leadernode` 추가. regular 의 dial
    대상이 DNS 로 정상 resolve 되는 것까지 확인 (E2E 검증 ✅).
  - **Bug #6b 근본 원인 정교화**: volume persist 뿐 아니라, 빈 named
    volume 최초 마운트 시 이미지 레이어의 default `leadernode.bin` 이
    volume 으로 자동 복사된다는 Docker 동작이 추가 트리거. 해결은
    `BootstrapDRBPeerIDFiles()` 호출 직후 `docker compose restart
    drb-leader drb-regular-*` 로 새 key 를 강제 reload.
  - **Bug #7 신규 섹션** (미해결, Bug #1 동일 class):
    `readBedrockDeployConfigTemplate` (`shutdown.go:311-312`) 가
    `<deploy>/tokamak-thanos/packages/tokamak/contracts-bedrock/scripts/deploy-config.json`
    레거시 경로를 강제로 읽음. 새 tokamak-deployer 는 이 경로에 쓰지 않음 →
    orchestrateDRBOperators 진입 시 파일 없음으로 차단. Fix B/C runtime
    재현이 이 버그로 막혀 다음 세션으로 이월.
  - **상태 테이블 추가**: 7개 버그 각각의 코드 수정 / runtime 확인 상태를
    문서 상단 "현재 상태 요약" 에 표로 정리.
  - **관련 커밋 섹션 업데이트**: trh-sdk `0f453c3` + trh-backend `f732a48`
    + plan file 링크 추가.

실제 배포 드라이브 결과 (2026-04-18): Bug #5/#6a/#6b 코드 수정은
적용되었으나 Bug #7 이 orchestrator 진입 이전에 차단 → Fix B (restart) 와
Fix C (volume reinit) 의 runtime 경로는 한 번도 실행되지 않음. 다음
세션에서 Bug #7 consumer-side 수정 후 Fix B/C 효과 검증 필요.

Tangential: trh-backend 의 local Docker 배포는 이제 `deploy-infra` step 을
`deploy-local-infra` 라벨로 기록 (기존 모든 배포가 AWS 라벨로 기록되던
혼선 제거, commit `f732a48`).

## [2026-04-18] update | drb-local-compose-path-template-bugs — Bug #4 확정 + Bug #6 신규 (2 sub-bug)

Updated page: [[drb-local-compose-path-template-bugs]] (troubleshooting/)
Source: 2026-04-17 후속 세션, trh-sdk commit 3912799

Changes:
  - **Bug #4 상태 "미확정" → "확정"**: DRB-node upstream `config/env.go`
    확인 결과 regular 바이너리 env 키는 `EOA_PRIVATE_KEY` / `LEADER_IP` /
    `PORT` (PORT 는 이름 OK, 나머지는 template 이 잘못된 이름 사용 중이
    었음). trh-sdk `3912799` 에서 수정.
  - **Bug #6 신규 섹션** (미해결, 2 sub-bug):
    - **6a**: `tokamaknetwork/drb-node:sha-8c37f63` 바이너리에
      `/dns/leadernode/tcp/%s/p2p/%s` format string 하드코딩. LEADER_IP
      env 지원 이전 버전 → upstream 최신 tag 로 업그레이드 필요.
    - **6b**: `drb-leader-keys` volume 에 이전 배포의 `leadernode.bin`
      (68B) 잔존 → leader 컨테이너가 구 key 로드해 구 PeerID 노출.
      template 은 새 PeerID 박아 불일치 dial 실패. `BootstrapDRBPeerIDFiles()`
      overwrite 보장 또는 volume clean 필요.

실제 배포 드라이브 결과: regular 컨테이너가 Bug #1-4 모두 통과하고
libp2p dial 단계까지 진행. Leader 컨테이너의 predeploy 호출 성공
(`Fetched current round from contract: 0`, `s_isInProcess value: 2`)으로
`0x4200...0060` CommitReveal2L2 가 live L2 에서 작동함이 확인됨.

## [2026-04-18] ingest | drb-local-compose-path-template-bugs — DRB preset 배포 5개 경로·템플릿 버그

New page: [[drb-local-compose-path-template-bugs]] (troubleshooting/)
Source: 2026-04-17 preset resume-deploy 세션 관찰 + trh-sdk commit 50d0b39

Index updated: Troubleshooting 표에 항목 추가
Decisions updated: [[deploy-methods-comparison]] 관련 문서에 링크 추가

Key facts captured:
  - **Bug #1**: `local_network.go:259,260,599` — `tokamak-thanos/build/{genesis,rollup}.json` 경로는 2026-04-16 `generate-genesis` 리팩토링 후 레거시. 소비자 측 consumer 수정
  - **Bug #2**: `local_network.go:431` — `{{ add ... }}` 사용인데 FuncMap 미등록으로 Go text/template 파싱 실패
  - **Bug #3**: `templates/local-compose.yml.tmpl:457,474` — range 내부 `.DRBNodeImage`/`.L2ChainID` 는 DRBRegular 구조체를 가리켜 평가 실패. `$.X` 로 root 접근 필요
  - **Bug #4 (미확정)**: Regular 노드 crash `PORT not set in environment variables`. template `PORT=9601` 으로 rename 했어도 재현. DRB-node source 에서 실제 env 키 확인 필요
  - **Bug #5 (미해결)**: resume 시 op-geth chaindata 재사용으로 L2 genesis hash mismatch. `initLocalOpGeth` 의 hash 재초기화 로직이 이 경로에서 발동하지 않음
  - Leader 노드 로그가 `Fetched current round from contract: 0` + `s_isInProcess value: 2` 를 남기면 `0x4200...0060` predeploy 는 이미 live L2 에서 호출 가능한 상태

## [2026-04-18] ingest | deploy-methods-comparison — Deploy.s.sol vs tokamak-deployer

New page: [[deploy-methods-comparison]] (decisions/) — 271 lines, 5-page tight spec
Source: 코드베이스 라인 단위 분석 (Deploy.s.sol 2031L + L2Genesis.s.sol 571L + start-deploy.sh 517L + contracts.go 588L + gasprice.go 92L + generator.go 126L + deployer_binary.go 231L + deploy_contracts.go 522L + genesis_prep.go 178L)

Index updated: Decisions 섹션에 deploy-methods-comparison 항목 추가

Key facts captured:
  - 전환 커밋: df52538 (2026-04-16, L1 경로 교체), 230cdb8 (2026-04-17, v0.0.5 고정 가스)
  - 성능 개선: Sepolia 배포 25-30분 → 6-8분 (fault-proof OFF 기준)
  - **중요 — 하이브리드 전환 상태**: trh-backend/preset_deploy.go:127 `EnableFaultProof: true` 하드코딩으로 Preset 배포 100% 가 fault-proof ON → 여전히 tokamak-thanos clone + forge 빌드 + cannon prestate + AnchorStateRegistry 소스 패치 경로 사용
  - tokamak-deployer v0.0.5 fault-proof 지원은 "반쪽 포팅": DisputeGameFactoryProxy + AnchorStateRegistryProxy 의 deploy + plain upgrade 까지만. initialize/setImplementation/Safe wallet 실행 은 여전히 forge 경로
  - L1 `initialize()` 호출 갭: contracts.go:202 "Try upgrade() first (simpler, no initialization)" — Foundry 경로의 `_upgradeAndCallViaSafe` 대체 메커니즘이 문서화되지 않음
  - 향후 포팅의 실질 장애물: GnosisSafe `execTransaction` Go 포팅 / cannon prestate 의 Rust+MIPS 빌드 의존성 / AnchorStateRegistry.sol 소스 패치

## [2026-04-09] init | Wiki initialized
Pages created: [[index]]
Schema defined: CLAUDE.md
Note: All component/concept/workflow/decision/troubleshooting pages are stubs pending first ingest.

## [2026-04-09] ingest | trh-platform/docs/ (Phase 2 migration)
Sources added to raw/architecture/:
  tech-stack.md, presets-implementation.md, local-l2-deployment-test-guide.md,
  e2e-deployment-test-guide.md, preset-deployment-flow.html, trh-deployment-flow.html,
  crosstrade-deploy-flow.html, install-guide.html

Pages created:
  [[architecture]], [[trh-platform]], [[trh-sdk]], [[trh-backend]], [[trh-platform-ui]],
  [[presets]], [[l2-deployment]], [[keystore]], [[l2-deploy-local]],
  [[sequential-l2-deploy]], [[port-conflicts]], [[l1-gas-limits]]

Pages still stub (raw source 없음):
  [[docker-health-checks]], [[l2-deposit-verification]]

## [2026-04-09] ingest | crossTrade/ (CrossTrade integration)
Sources added to raw/decisions/:
  PRD-CrossTrade-TRH-Integration-v2.1.md, Genesis-Predeploy-Storage-Analysis.md

Pages created:
  [[cross-trade]], [[deposit-tx]],
  [[deposit-tx-vs-genesis-predeploy]], [[abigen-vs-manual-calldata]],
  [[separate-compose-for-crosstrade]]

Key facts captured:
  - CrossTrade: DeFi/Full Preset만 (Gaming 제외 — PRD v2.1 수정사항)
  - L2 컨트랙트 배포: L1 Deposit Tx (12 트랜잭션, ~5분)
  - Genesis Predeploy 거부: constructor 미실행 + 15개 스토리지 슬롯 수동 계산 필요
  - ABI 패턴: abigen (OptimismPortal 직접 호출) + abi.Pack (L2 calldata)
  - dApp: docker-compose.crosstrade.yml 별도 파일 (v3.8 호환)

## [2026-04-09] ingest | Thanos 인프라 레포 3종 추가
Sources: 각 레포 소스 코드 직접 탐색 (raw source 없음)

Pages created:
  [[tokamak-thanos]], [[tokamak-thanos-stack]], [[tokamak-thanos-geth]]

Pages updated:
  [[architecture]] — Thanos 인프라 레이어 추가, 데이터 흐름 다이어그램 확장,
                     Shared Technology 테이블 확장, EKS 배포 타겟 추가
  [[index]] — Thanos 인프라 서브섹션 신설

Key facts captured:
  - tokamak-thanos: OP Stack v1.7.7 포크, Go 1.24 + TS 5.4.5, Nx 모노레포
  - tokamak-thanos-stack: Terraform + Helm IaC, EKS + 6개 Helm 차트
  - tokamak-thanos-geth: go-ethereum v1.16.3 포크, Deposit TX (0x7E), Engine API 8551
  - 전체 7개 레포 아키텍처 맵 완성

## [2026-04-09] ingest | 신규 레포 4종 추가 (integration 3 + core 1)
Sources: 각 레포 소스 코드 직접 탐색

Pages created:
  integration/ → [[thanos-bridge]], [[commit-reveal2]], [[drb-node]]
  core/ → [[tokamak-rollup-hub-v2]]

Pages updated:
  [[index]] — Core/Integration 서브섹션 재구성, 4개 신규 항목 추가

Key facts captured:
  - thanos-bridge: Next.js 15 DApp, @tokamak-network/thanos-sdk 0.0.14-dev, Wagmi/Viem
  - commit-reveal2: Solidity 0.8.30, Foundry, 2단계 Commit-Reveal, last revealer attack 방지
  - drb-node: Go 1.23, libp2p, Leader/Regular 2노드 아키텍처, PostgreSQL 영속성
  - tokamak-rollup-hub-v2: Next.js 16 마케팅 사이트, Three.js 3D, GitHub API로 trh-platform 릴리즈 조회

## [2026-04-09] ingest | .planning/ → trh-wiki (CrossTrade 프로젝트 지식 이전)
Sources added to raw/:
  raw/architecture/deployment-pitfalls.md  ← .planning/research/PITFALLS.md
  raw/architecture/testing-guide.md        ← .planning/codebase/TESTING.md

## [2026-04-16] ingest | tokamak-deployer v1.0.1 logging improvements
Sources: tokamak-thanos feat/tokamak-deployer branch

Pages created:
  [[tokamak-deployer-logging]] — Comprehensive logging for debugging contract deployment hangs

Pages updated:
  [[index]] — Added tokamak-deployer-logging to Troubleshooting section

Key facts captured:
  - tokamak-deployer v1.0.0 had zero logging, making hangs undiagnosable
  - v1.0.1 adds 50+ log statements across two levels:
    * High-level: step progress (Step X/32), deployer address, L1 RPC connection
    * Low-level: transaction hashes, gas prices, block confirmations, deployed addresses
  - Enables root cause analysis of deployment hangs and silent failures
  - trh-sdk version pinned updated from v1.0.0 to v1.0.1
  raw/decisions/tech-debt-and-risks.md     ← .planning/codebase/CONCERNS.md
  raw/decisions/requirements-v1.md         ← .planning/REQUIREMENTS.md

Pages created:
  [[l1-deposit-tx-pitfalls]] — L1 Deposit Tx CrossTrade 배포 13개 함정 (Critical/Moderate/Minor)
  [[testing]] — Vitest + Playwright 테스트 스택, 3가지 E2E 모드, 핵심 패턴
  [[tech-debt-and-risks]] — Known bugs, security concerns, dependencies at risk, test coverage gaps
  [[requirements-v1]] — CrossTrade 통합 v1 요구사항 30개 + Phase traceability

Pages updated:
  [[index]] — Workflows, Decisions, Troubleshooting 섹션에 5개 신규 항목 추가

.planning 정리:
  삭제: research/, codebase/, phases/01~04/, quick/, debug/, REQUIREMENTS.md
  유지: phases/05/ (E2E Phase 미완료), PROJECT.md, ROADMAP.md, STATE.md

## [2026-04-17] fix | tokamak-deployer release pipeline — monorepo tag format support
Problem: Pushing `tokamak-deployer-v0.0.1` tag was creating GitHub Release `v1.0.2` instead of `v0.0.1`
Root causes: 4 cascading issues in CI/CD configuration

Solutions implemented:
  1. Goreleaser strict tag validation → Added `--skip-validate` flag
  2. Invalid trimPrefix template function → Removed; use workflow env var extraction instead
  3. Hardhat build failure on missing foundry.lock → Removed unnecessary `pnpm install`
  4. Goreleaser changelog generation failure → Added `changelog: {skip: true}`

Commits:
  - 45a4b520da: remove pnpm install from build contracts step
  - cd12b6d146: add --skip-validate flag to goreleaser
  - e73b9d3312: remove invalid trimPrefix template function
  - 62a6e6a5a5: disable changelog generation for monorepo-scoped release

Outcome: ✓ v0.0.1 release successfully created with all 4 platform binaries
  - tokamak-deployer-darwin-amd64.tar.gz
  - tokamak-deployer-darwin-arm64.tar.gz
  - tokamak-deployer-linux-amd64.tar.gz
  - tokamak-deployer-linux-arm64.tar.gz
  - checksums.txt
  - Incorrect v1.0.2 release deleted

Key learning: Workflow files must exist on default branch before tag push to trigger workflow
  Problem: Tag pushed before workflow changes merged → workflow never ran
  Solution: Merge workflow changes to main first, then push tag to trigger workflow

## [2026-04-17] update | tokamak-deployer release pipeline — slash-separated tag format migration
Motivation: Standardize monorepo tag naming to use path-like format (e.g., `component/version`) instead of dash separators
Prior state: Used `tokamak-deployer-v0.0.1` format; now migrating to `tokamak-deployer/v0.0.1`

Changes made (on top of prior dash-format work):
  1. Workflow trigger pattern: `'tokamak-deployer-v*'` → `'tokamak-deployer/v*'`
  2. Version extraction: `VERSION=${TAG#tokamak-deployer-}` → `VERSION=${TAG#tokamak-deployer/}`
  3. Release name template: `.goreleaser.yml` added `release.name_template: "tokamak-deployer/{{ .Version }}"`

Outcome: ✓ tokamak-deployer/v0.0.1 release successfully created
  - Tag format: tokamak-deployer/v0.0.1 (slash-separated path format)
  - Release name: tokamak-deployer/v0.0.1 (matches tag format exactly)
  - All 4 platform binaries uploaded with correct naming
  - Checksums.txt included
  - Incorrect v1.0.2 release removed from prior session

Key design decision: Monorepo components should use slash-separated tags (e.g., `tokamak-deployer/v0.0.1`, `thanos-bridge/v1.0.0`)
  Rationale: Path-like format (`component/version`) is more maintainable than dash-separated format across multiple repos
  Pattern applies to: All future releases in tokamak-thanos and related monorepos
  Risk: Requires workflow file existence on default branch before tag push (precondition met in this session)

## [2026-04-09] refactor | raw/ 드롭존 구조 개편
HTML 다이어그램 에셋 분리 및 inbox/ 드롭존 추가

Files moved:
  raw/architecture/*.html (4개) → raw/assets/

New directories:
  raw/inbox/     ← 신규 문서 드롭존 (분류 전 보관)
  raw/assets/    ← HTML 다이어그램 및 이미지 에셋

CLAUDE.md 업데이트:
  - raw/ 디렉토리 레이아웃 설명 갱신
  - inbox/ 드롭존 워크플로우 명시
  - wiki/components/ core/integration 서브섹션 반영
  - 컴포넌트 canonical names 12개 레포로 확장

## [2026-04-11] update | CrossTrade E2E 테스트 스위트 완성 반영
Pages updated:
  [[testing]] — CrossTrade Live TX 테스트 섹션 신설 (CRT-01~07 전체 통과 기록),
               EIP-6963 mock provider 주입 패턴 추가,
               crosstrade-tx.live.spec.ts 파일 구조에 추가
  [[cross-trade]] — E2E 테스트 섹션 신설 (테스트 ID × 컨트랙트 대응 테이블, 가스 정책)
  [[l1-gas-limits]] — provideCT 관련 행 2개 추가 (auto estimation),
                      "explicit gasLimit 제거 배경" 섹션 신설

Key facts captured:
  - CRT-01~07 전체 통과 (2026-04-11)
  - L1 provideCT gasLimit: explicit 제거 → ethers.js 자동 추정 (commit: 8ec40d8)
  - L2-L2 provideCT: CDM 2회 overhead → ~800k (explicit 제거 후 자동 추정으로 해결)
  - CRT-07: EIP-6963 eip6963:announceProvider 이벤트로 mock wallet 주입 패턴 확립
  - _minGasLimit 파라미터(CDM relay용 200k)는 L1 TX gasLimit과 별개

## [2026-04-10] ingest | raw/inbox/crosstrade-deployment-guide.md
Source: crossTrade/docs/deployment-guide.md (Foundry 기반 배포 가이드)

Pages updated:
  [[cross-trade]] — 운영 함정 섹션 추가 (admin key 잠김, L2-L2 proxy-direct setChainInfo 함정)
  [[l1-deposit-tx-pitfalls]] — Pitfall #14 추가 (upgradeTo 없이 setChainInfo만 성공하는 silent broken 상태)

Pages deleted:
  [[crosstrade-deployment]] — raw 재포맷에 불과, 비자명한 인사이트만 기존 페이지에 흡수

Key facts captured (비자명한 것만):
  - Admin key 없으면 기존 프록시에 새 체인 영구 등록 불가 → 재배포 필요. 사전에 isAdmin() 확인 필수.
  - L2toL2CrossTradeProxy.setChainInfo는 proxy-direct 구현 → implementation() == 0x0에서도 성공. 나머지 함수는 impl 위임 → silent broken 상태 가능.
  - 실제 발생: ect-defi L2toL2CrossTradeProxy(0x2452ceB6...) 이전 세션에서 setChainInfo 성공했으나 upgradeTo 미실행 → chainData() revert로 뒤늦게 발견.

## [2026-04-13] ingest | thanos-bridge 로컬 Docker 배포 트러블슈팅
Sources added to raw/sessions/:
  debug-network-switch-failure-on-local-bridge-withdraw.md
  debug-env-vars-not-applied-localhost-3001-bridge.md
  debug-bridge-info-data-truncated-with-ellipsis.md
  debug-withdraw-network-switch-balance-zero.md

Pages created:
  [[thanos-bridge-local-docker-deployment]] — 로컬 Docker 배포 시 발생하는 4가지 문제 트러블슈팅

Key facts captured:
  - next-runtime-env는 빌드 타임이 아닌 런타임에 NEXT_PUBLIC_* 읽음 → Next.js standalone 모드에서 docker run -e 플래그 필수
  - host.docker.internal은 컨테이너 내부에서만 동작, 브라우저(wagmi)에서는 localhost 사용 필요
  - isHTTPS() 유틸: localhost / 127.0.0.1 / host.docker.internal 모두 허용 (useNetwork.ts에서 사용)
  - BridgeInfoItem truncate 버그: Chakra UI truncate prop + maxWidth 제거로 수정

## [2026-04-14] ingest | workflows/ec2-deploy.md (AWS L2 deploy flow)
Sources: trh-platform/src/main/{aws-auth,webview,webview-preload,index}.ts,
         trh-backend/pkg/{api,services,stacks}/thanos/*,
         trh-sdk/pkg/{stacks/thanos,cloud-provider/aws}/*

Page filled: [[ec2-deploy]] (replaces 2026-04-09 stub)
Scope: 6-Phase 전체 경로 — Electron SSO creds 획득 → Next.js POST → trh-backend goroutine (TaskManager) → trh-sdk Foundry L1 deploy → trh-sdk Terraform+Helm 2-pass on EKS

Key facts captured:
  - Electron은 "자격증명 전달자"일 뿐. 실제 배포는 임베디드 Next.js UI → localhost:8000 HTTP 직통.
  - 자격증명 전달 경로: SSO temp creds → window.__TRH_AWS_CREDENTIALS__ JS 글로벌 → POST body
  - trh-backend는 trh-sdk를 Go 모듈로 import (셸아웃 아님). in-process goroutine으로 순차 실행.
  - trh-sdk AWS 경로: Foundry(L1) → Terraform 2단계(S3+DynamoDB backend, VPC+EKS+EFS) → Helm 2-pass(PVC → workloads) → ingress 폴링
  - SSH/raw EC2 없음. 모든 L2 노드는 EKS Helm 파드. "ec2-deploy" 명칭은 레거시.
  - Gotchas: AWS creds Postgres 평문 저장, SSO 토큰 리프레시 없음(1h TTL), DTO required-field 비일관성, trh-sdk static creds only

## [2026-04-15] housekeeping | aws-sso 삭제 + 미작성 페이지 3종 ingest
Pages deleted: [[aws-sso]] (참조 5곳 제거 — keystore, index, ec2-deploy, trh-platform×2)
New pages: [[docker-compose-lifecycle]], [[local-dev]], [[release]]
Key additions:
  - docker-compose-lifecycle: Preset별 compose file 분기, 컨테이너 포트 목록, 레이어 구조
  - local-dev: 레포별 개발 서버 기동법, VITE_MOCK_ELECTRON/ELECTRON_USE_BUILD 환경 변수
  - release: Electron DMG/NSIS/AppImage 빌드 타겟, GitHub Releases 연동, Docker Hub 패턴

## [2026-04-15] update | trh-platform-ui Preset Wizard 2-step 간소화
Pages updated: [[trh-platform-ui]]
Changes:
  - 배포 위자드 플로우: Preset Mode 4-step → 2-step (Step1: Preset 선택, Step2: Basic Info & Deploy)
  - 입력 필드: 26개 → 5개 (presetId, chainName, network, awsAccessKey, awsSecretKey)
  - 제거 항목: seedPhrase, l1RpcUrl, l1BeaconUrl, feeToken, infraProvider, reuseDeployment, awsRegion
  - Classic Mode(4-step) 설명 추가 (기존 유지)
Key decision: 시스템이 L1 인프라 및 계정 설정 자동 결정 → 사용자 입력 최소화 (docs/preset-deploy-prd.md 기반)

## [2026-04-15] ingest | DRB-node + Commit-Reveal2 repo analysis
Pages updated: [[drb-node]], [[commit-reveal2]], [[index]]
New pages: [[drb-project]]

## [2026-04-15] ingest | op-batcher blob fee spike fix
New pages: [[op-batcher-blob-fee-spike]] (troubleshooting/)

## [2026-04-15] ingest | preset-deploy 409 트러블슈팅
New pages: [[preset-deploy-409]] (troubleshooting/)
Pages updated: [[l2-deploy-local]] — 알려진 이슈 섹션에 [[preset-deploy-409]] 링크 추가
Code fix: trh-platform-ui/src/features/rollup/hooks/usePresetWizard.ts — catch 블록이 handleApiError plain object의 message 필드를 직접 읽도록 수정 (기존: instanceof Error fallback으로 generic 메시지만 표시됨)
Key facts:
  - 원인: calcBlobFeeCap 하드코딩 2×, suggestGasPriceCaps→finishBlobTx 사이 stale cap
  - 해결: BlobFeeCapMultiplier(4×) + MaxBlobBaseFee(50 gwei) 임계값 플래그 추가
  - retry.Unrecoverable로 ErrBlobBaseFeeTooHigh 발생 시 30회 retry 없이 즉시 재큐
  - tokamak-thanos commit 8e67bbce, trh-sdk commit 13e1465
  - OP_BATCHER_DATA_AVAILABILITY_TYPE=calldata 임시 우회 해제됨
Key additions: DRB umbrella page — shared protocol flow (8 success + 23 failure paths), round state machine (IN_PROGRESS 6-branch HALTED), operator lifecycle (32 max, X8 slash accounting, notInProcess gate), dispute/slashing matrix, L2 gas model (CommitReveal2L2 + OVM oracle), ABI sync workflow (수동 복사 + abigen), environment matrix (Sepolia/OpSepolia/ThanosSepolia), integration test harness reference (128KB docker_nodes_quick_test.go, failure/stress/perf suites).

## [2026-04-15] fix | 로컬 L2 재배포 불가 버그 수정 (DB↔Docker 상태 불일치)
Repos: trh-backend (e70ebec, 8065a0f), trh-sdk (6077386)
Pages updated: [[tech-debt-and-risks]] — Known Bugs 섹션에 해결 기록

Root cause 1: `checkNoActiveLocalStack()` DB만 확인 → 컨테이너 없어도 409 반환
Root cause 2: `destroyLocalNetwork()` compose 파일 없을 때 nil 반환 → 볼륨 고아 상태

Fix A (trh-backend): `docker ps --filter label=com.docker.compose.project=<uuid>` 조회 추가.
  컨테이너 없으면 DB 자동 Terminated 보정 → 새 배포 허용.
Fix C (trh-sdk): compose 파일 없을 때 `docker volume rm -f trh-local-config trh-local-monitoring <uuid>_op-geth-data` 직접 실행.

## [2026-04-15] update | CrossTrade dApp 버그 픽스 3종 — defi-eth 프리셋 환경
Sources: trh-sdk commits 8af71e6, trh-backend commit e13669c, crossTrade commit 1103393

Pages updated:
  [[cross-trade]] — dApp 환경변수 포맷 변경, Thanos Sepolia destination_chains 설계 결정,
                    destination picker 버그 픽스, defi-eth native token 메타데이터 버그 픽스 섹션 추가

Key facts captured (비자명한 것만):
  - OKX 등 지갑은 서명 팝업 전 eth_estimateGas로 사전 시뮬레이션 → 컨트랙트 revert시 팝업 자체를 차단 ("서명이 안된다" 증상)
  - Thanos Sepolia L2toL2CTProxy(0x7BbEC...) 에는 우리가 배포한 신규 L2 chain ID가 미등록 → Thanos→신규L2 방향 시뮬레이션 revert
  - 해결: thanosL2L2Tokens destination_chains: [] → UI가 해당 경로를 애초에 차단
  - NEXT_PUBLIC_CHAIN_CONFIG (구버전) → NEXT_PUBLIC_CHAIN_CONFIG_L2_L1 + NEXT_PUBLIC_CHAIN_CONFIG_L2_L2 로 분리. trh-sdk local-compose.yml.tmpl도 동기화 (이전에 env var 이름 불일치로 L2_L2 config가 dApp에 전달되지 않았음)
  - L2_L2 토큰 포맷: [{name, address, destination_chains}] 배열. L2_L1 토큰 포맷: {ETH: addr, USDC: addr} flat map — 두 포맷이 다름
  - defi-eth 프리셋: L2NativeTokenName/Symbol을 "Ethereum"/"ETH"로 분기. 미전달시 지갑에 체인 추가할 때 "TON"으로 잘못 표시됨
  - 반대 방향(신규L2 → Thanos Sepolia)은 정상 — 신규L2 proxy에는 우리가 admin, Thanos chain ID 등록 완료

## [2026-04-16] fix | op-batcher blob fee 에러 재발 — suggestGasPriceCaps hack 제거
Repo: tokamak-thanos commit d8202223
Pages updated: [[op-batcher-blob-fee-spike]] — 재발 원인 + 2차 수정 히스토리 추가

Root cause: `8e67bbce`의 MaxBlobBaseFee 임계값 체크가 `2a9e294c`의 `CalcBlobFeeCancun(0)` hack과 충돌.
  suggestGasPriceCaps가 1 wei를 반환 → 임계값 체크 항상 통과 → EstimateGas에 BlobGasFeeCap=1 wei 전달
  → Sepolia 실제 fee > 1 wei → "max fee per blob gas less than block blob gas fee" 재발

Fix: suggestGasPriceCaps에서 CalcBlobFeeCancun(0) 제거, 실제 *head.ExcessBlobGas 복원.
  이제 Sepolia 비정상 excessBlobGas → blobBaseFee >> 50 gwei → ErrBlobBaseFeeTooHigh 발동 → EstimateGas 건너뜀.

## [2026-04-15] update | trh-platform DeploymentWatcher — 배포 실패 원인 표시
Pages updated: [[trh-platform]]

Changes:
  - 핵심 역할에 "Deployment watcher" 추가 (6번)
  - 주요 모듈에 DeploymentWatcher + NotificationStore 링크 추가
  - DeploymentWatcher 섹션 신설: 감지 전환 테이블, 실패 원인 추출 흐름, AppNotification 인터페이스, 주의사항

Key facts captured:
  - `FailedToDeploy`/`FailedToUpdate` 감지 시 `/api/v1/stacks/thanos/:stackId/deployments?limit=1` → logs?limit=50 순차 호출
  - 로그 포맷: JSON Lines. 추출 우선순위: 마지막 level==="error" message → 마지막 raw 줄 → undefined
  - 로그 조회 실패 시에도 notification은 반드시 발송 (fetchFailureReason 전체 try-catch → undefined)
  - AppNotification 인터페이스에 `detail?: string` 추가 (main + renderer 양쪽)
  - URL 패턴: `/api/v1/stacks/thanos/{stackId}/...` — "thanos" 세그먼트 필수
  - NotificationPage.tsx: `detail` 있으면 알림 카드에 모노스페이스 빨간 텍스트로 인라인 표시

## [2026-04-16] ingest | thanos-deployer deployment logic analysis (final)
Sources: Complete code-level analysis from 45 files across 3 repos (tokamak-thanos, trh-sdk, trh-backend)

Page created:
  [[thanos-deployer-analysis]] — Executive summary with key findings, 8-layer architecture, 6-phase flow

Analysis documents added to tokamak-thanos/docs/analysis/:
  PHASE_2_ANALYSIS.md (37.4KB) — Web UI request → HTTP POST → trh-backend handler
  PHASE_3_ANALYSIS.md (57.2KB) — Backend queuing, TaskManager goroutine orchestration
  PHASE_4_ANALYSIS.md (55.9KB) — L1 contract deployment via Foundry (35+ contracts, 4 phases)
  PHASE_5_ANALYSIS.md (70.1KB) — L2 Genesis generation (op-chain-ops, 14+ steps, 40+ predeploys)
  PHASE_6_ANALYSIS.md (46.6KB) — Result persistence, StackMetadata updates, client notification
  code-reference-table.md (26.6KB) — 51 functions mapped across 45 files
  thanos-deployer-flow-analysis.md (48.9KB) — Main document with 6 appendices

Key facts captured (6 phases):
  - Phase 1: Electron SSO auth (AWS SigV4 token exchange)
  - Phase 2: Next.js embedded UI → POST /api/v1/stacks/thanos with DeployThanosRequest JSON
  - Phase 3: Go TaskManager enqueues → goroutine loop → sequential phase execution
  - Phase 4: trh-sdk calls start-deploy.sh (Foundry forge script) → deploy.json with 35+ contract addresses
  - Phase 5: op-chain-ops NewL2Genesis() reads deploy.json → bytecode patching → genesis.json/rollup.json
  - Phase 6: UpdateStackMetadata() writes to DB → webhook notification → UI notification

Critical pitfalls documented:
  1. Blob fee spike (excessBlobGas edge case) — tokamak-thanos commit d8202223 fix
  2. Bytecode patching (hardcoded offsets per Openzeppelin version)
  3. Environment validation (missing .env checks → zero contract addresses)
  4. Cross-Trade scope isolation (local-only vs L2-L2 cross-chain)
  5. Hard fork compatibility (Ecotone/Fjord/Granite mismatch)

Risk analysis: 3 high, 3 medium, 2 low risks with mitigation strategies.
Call depth: 8+ synchronous calls from HTTP handler to op-chain-ops.
Data transformations: JSON → .env → deploy.json → op-chain-ops → genesis.json (3 steps).
State mutations: 6 major transforms, 14+ predeploy bytecode operations.

Analysis scope: Electron → trh-backend → trh-sdk → Foundry → op-chain-ops → StackMetadata → Client.
Not covered: AWS infrastructure, Solidity implementation details, local Docker deployment.

Verification checklist included (8 grep commands for validation).
Cross-references: blob fee fixes (tokamak-thanos commits), ec2-deploy, preset-system, design-decisions.

## [2026-04-17] perf | tokamak-deployer v0.0.5 — fixed gas price reuse (L1 deploy 5m47s on Sepolia)
Repos: tokamak-thanos (76b522c02e, tag tokamak-deployer/v0.0.5), trh-sdk (230cdb8)

Problem: v0.0.4 called `SuggestGasPrice` per TX (26-32 round-trips per deploy) and
started at the raw suggested price, so the 90s/5-attempt bump-retry safety net
fired often when Sepolia block-time drifted. Reported L1 deploy wall-clock:
~10-15 min.

Change: resolveGasPrice runs once at Deploy() startup. Default = SuggestGasPrice
× 200%, clamped to [1 Gwei, 100 Gwei]. Reused for every TX. sendMaxAttempts
5→3, sendAttemptTimeout 90s→180s (retry safety net still present but rarely
triggers).

New pages:
  [[tokamak-deployer-gas-price]] — Design decision, parameters, measured results,
                                   escape hatches, floor-applied-when-quiet note

Pages updated:
  [[tokamak-deployer-logging]] — v0.0.5 row added to version table; log format
                                  examples updated to new `Fixed gas price …
                                  user-specified` startup line + `attempt 1/3`
                                  broadcast line
  [[index]] — Troubleshooting section adds [[tokamak-deployer-gas-price]]

Measured (Sepolia, 2026-04-17, 0x7220c734653a…99c, nonces 1839-1864):
  - Total: 5m47s (347s) for 26 steps
  - 0 bump/retry events
  - Per-step avg 13.3s (median 12s, max 26s — within block variance)
  - Fixed gas price held at 1 Gwei (suggested 0.031 Gwei × 2 = 0.063 Gwei →
    floor of 1 Gwei kicked in; visible in logs as "user-specified" because
    trh-sdk passed it via --gas-price)
  - Deploy cost 0.0196 ETH

Key design decisions captured:
  - Multiplier 200 (trh-sdk also passes × 2 so balance precheck at × 3 keeps a
    wider affordability envelope than the 2× actually charged)
  - Floor 1 Gwei (guards v0.0.1 gasPrice=0 bug)
  - Ceil 100 Gwei (fails mainnet fast rather than bleeding budget)
  - `--gas-price` + `TOKAMAK_DEPLOY_GAS_PRICE` env mirror OLD forge
    `--with-gas-price` pattern (ops-bedrock/scripts/sepolia-oneclick.sh:253)

Next steps: track whether the retry path ever fires in production logs; if 0
after 1 month, consider tightening `sendMaxAttempts` further to 2.

## [2026-04-17] fix | tokamak-deployer gasPrice zero bug (v0.0.1 pre-release)
Repos: tokamak-thanos (451224b6aa), trh-sdk (567e617), trh-backend (30929b0)
Workflow: release-deployer.yml updated + CI/CD v0.0.1 tag trigger (Run #24523146838 in progress)

Root cause: `big.Int.Div(gasPrice, 1e9)` modifies receiver in-place.
  - Log line: `fmt.Printf("Suggested gas price: %v Gwei", gasPrice.Div(gasPrice, 1e9))`
  - Result: gasPrice destroyed (0), subsequent TX creation fails with "transaction underpriced: Suggested gas price: 0 Gwei"
  - Symptom observed: Sepolia L1 OptimismPortal deployment fails on AddressManager TX

Fix applied (commit 451224b6aa):
  - Changed: `gasPrice.Div(gasPrice, big.NewInt(1e9))`
  - To: `new(big.Int).Div(gasPrice, big.NewInt(1e9))`
  - Preserves original gasPrice for TX creation

CI/CD changes:
  - release-deployer.yml: Added `tokamak-deployer-v*` pattern to tag triggers (commit ff9aa87f8e)
  - Enables pre-release workflow for tokamak-deployer-v0.0.1 tag (v0.0.x format to avoid monorepo name collision)
  - Rationale: tokamak-deployer is a separate binary tool, not monorepo version

Dependency chain synchronized:
  - trh-sdk TokamakDeployerVersion: "v0.0.1" (commit 567e617)
  - trh-backend go.mod: Points to trh-sdk commit 567e617a633d (30929b0)

Verification pending:
  - GitHub Release v0.0.1 creation (Run #24523146838 in progress)
  - Binary artifacts: tokamak-deployer-{linux,darwin}-{amd64,arm64}.tar.gz
  - Pre-release flag status

## [2026-04-17] ingest | DRB Gaming Enablement v1.1 milestone

Pages updated:
  [[commit-reveal2]] — Genesis Predeploy 방식 (trh-sdk 전용) 섹션 추가
  [[drb-node]] — 환경 변수 표 확장 (LEADER_EOA/LEADER_PORT/LEADER_PEER_ID/LEADER_MULTIADDR/STATUS)
  [[drb-project]] — Known Quirks 갱신 (SDK peer ID 결정적 파생, Leader+3Regular 고정 구성)
  [[l2-deployment]] — Gaming/Full Preset 추가 단계 섹션 신설 (DRB 통합 전체 흐름)

Key facts captured:
  - Gaming/Full preset에서 CommitReveal2L2 genesis predeploy (0x4200…0060, ERC1967 proxy)
  - Regular 3대 BIP44 index 5/6/7 결정적 파생 + libp2p Ed25519 peer ID 결정적 파생
  - Genesis alloc funding (runtime 송금 회피, max(threshold×10, 1e18)) + 순차 depositAndActivate() 자동 호출
  - trh-sdk Makefile `update-drb-contracts VERSION=<semver>` 타겟 + `DRB_CONTRACTS_VERSION` env override
  - 구현: trh-sdk/pkg/stacks/thanos/drb_{genesis,orchestrator,activate,peer_id}.go
