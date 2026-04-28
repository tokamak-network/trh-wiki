---
updated: 2026-04-28
sources:
  - commit 50d0b39 (trh-sdk main)
  - commit 3912799 (trh-sdk main)
  - commit 0f453c3 (trh-sdk main)
  - commit 4c3e33b (trh-sdk main)
  - commit f732a48 (trh-backend main)
related:
  - "[[deploy-methods-comparison]]"
  - "[[drb-project]]"
  - "[[drb-node]]"
  - "[[l2-deploy-local]]"
tags: [troubleshooting, drb, local-compose, gaming-preset]
---

# DRB Gaming Preset 로컬 배포 — 7 + 1 경로·템플릿 버그

2026-04-17 preset resume-deploy (gaming + USDT + fault-proof ON) 시 순차적으로
드러난 7개 독립 버그 + 2026-04-18 runtime 검증 세션에서 드러난 Bug #8. 1-4 는
commit `50d0b39` + `3912799` 에서 수정. 5/6a/6b 는 commit `0f453c3` 에서
수정. 7 은 commit `4c3e33b` 에서 수정. 8 은 tokamak-thanos
`7af425cdf4` (v0.0.6 release) + trh-sdk (다음 커밋) 에서 수정.

## 현재 상태 요약

| Bug | 증상 요약 | 코드 수정 | Runtime 확인 |
|---|---|---|---|
| #1 | genesis/rollup 경로 불일치 | `50d0b39` | ✅ |
| #2 | `add` 템플릿 함수 미등록 | `50d0b39` | ✅ |
| #3 | range 내부 root-scope 접근 실패 | `50d0b39` | ✅ |
| #4 | Regular 노드 env 키 이름 | `3912799` | ✅ |
| #5 | op-geth volume stale (host 경로 probe 오류) | `0f453c3` Fix C | ✅ **2026-04-18 verified** (`skipping init` branch) |
| #6a | Hostname `leadernode` 하드코딩 | `0f453c3` Fix A (alias) | ✅ DNS 해결 확인 |
| #6b | Leader PeerID mismatch (image-default key) | `0f453c3` Fix B (restart) | ✅ **2026-04-28 verified** (수동 bootstrap → leadernode.bin 교체 → 재시작; 단 trh-backend:latest 이미지 미포함 — 수동 workaround 필요, 아래 참고) |
| #7 | `readBedrockDeployConfigTemplate` 레거시 경로 | `4c3e33b` (new-path-first + legacy fallback) | ✅ **2026-04-18 verified** (간접: anchor init 도달) |
| #8 | Fault-proof 컨트랙트 미배포 + deploy-output → deployments/ 파일 격차 | tokamak-thanos `7af425cdf4`/`8b0473bf12` + trh-sdk `f009dbc`/`6c8da80`/`2a688a8` | ✅ code-complete + anvil/fixture verified (Sepolia 재배포 필요) |

## Bug #1 — Genesis/Rollup 경로 불일치

**증상**: `failed to generate docker compose file: required file missing:
<deploy>/tokamak-thanos/build/genesis.json (run deploy-contracts first)`

**근본 원인**: 2026-04-16 `generate-genesis` 리팩토링으로 생성자는
`<deploy>/genesis.json` 에 저장하도록 바뀌었지만, `local_network.go` 의 소비자
측이 레거시 경로를 그대로 읽고 있었음.

**수정** (`pkg/stacks/thanos/local_network.go:259,260,599`):
`tokamak-thanos/build/{genesis,rollup}.json` → `<deploy>/{genesis,rollup}.json`

## Bug #2 — `add` 템플릿 함수 미등록

**증상**: `failed to parse compose template: template: local-compose:471:
function "add" not defined`

**근본 원인**: 템플릿의 `REGULAR_PORT: {{ add 9600 $r.Index }}` 가 Go
`text/template` 의 기본 함수셋에 없는 `add` 를 호출. `sprig` 같은 헬퍼 없이
`Funcs` 로 등록하지 않으면 파싱 단계에서 실패.

**수정** (`pkg/stacks/thanos/local_network.go:431`):

```go
tmpl, err := template.New("local-compose").Funcs(template.FuncMap{
    "add": func(a, b int) int { return a + b },
}).Parse(localComposeTmpl)
```

## Bug #3 — range 내부 root-scope 접근 실패

**증상**: `executing "local-compose" at <.DRBNodeImage>: can't evaluate
field DRBNodeImage in type thanos.DRBRegular`

**근본 원인**: `{{ range $i, $r := .DRBRegulars }}` 블록 안에서 bare dot(`.`)
은 루프 아이템(`DRBRegular`) 을 가리키므로 root 필드인 `.DRBNodeImage`·
`.L2ChainID` 는 평가되지 않음. 같은 블록에 이미 `$.DRBLeaderPeerID` 가
쓰이고 있어 관례는 확립돼 있었으나 두 필드만 누락.

**수정** (`templates/local-compose.yml.tmpl:457,474`): `.X` → `$.X`.

## Bug #4 — Regular 노드 env 키 이름 (확정 완료, `3912799`)

**증상**: 템플릿에 `PORT=9601` 를 세팅해도 DRB-node 가
`PORT not set in environment variables` 로 crash.

**근본 원인**: DRB-node upstream `config/env.go:135-144` 확인 결과, regular
바이너리가 실제로 읽는 env 키는 3 개. template 과 불일치:

| 템플릿 (이전) | 실제 (DRB-node 소스) |
|---|---|
| `REGULAR_PRIVATE_KEY` | `EOA_PRIVATE_KEY` |
| `REGULAR_EOA` | (DRB-node 가 안 읽음) |
| (누락) | `LEADER_IP` — dial 대상 hostname. 누락 시 `log.Fatal("LEADER_IP is not set")` |
| `PORT` | `PORT` (일치, OK) |

**수정** (`templates/local-compose.yml.tmpl:466-467`, commit `3912799`):
- `REGULAR_PRIVATE_KEY` → `EOA_PRIVATE_KEY`
- `REGULAR_EOA` 제거
- `LEADER_IP: "drb-leader"` 추가

**검증**: regular 컨테이너가 env init 통과 → `Successfully inserted/updated
NodeInfo: EOA=0x..., Port=9601, PeerID=...` 까지 진행. `PORT not set` crash
사라짐. 이어지는 dial 실패는 Bug #6 (별도).

## Bug #5 — op-geth volume stale (코드 수정, runtime 미확인)

**증상**: resume 재시도 시 op-node 가
`expected L2 genesis hash to match L2 block at genesis block number 0:
<hash_in_geth_chaindata> <> <hash_in_new_genesis.json>` 로 crash.

**근본 원인**: `local_network.go:600-622` 의 hash 기반 재초기화 로직이
`os.Stat(<deployPath>/op-geth-data/chaindata)` 로 host 파일시스템을
probe 하고 있었음. 그러나 op-geth-data 는 **Docker named volume** (docker
volume inspect 에만 나타남) 으로, host 경로는 애초에 존재하지 않음 → probe
는 항상 실패 → 스테일 체크도 `.genesis-hash` 재기록도 발동하지 않음.
결과적으로 resume 때 op-geth 는 이전 배포의 chaindata 를 그대로 들고
부팅하고, 새 genesis.json 과 해시가 불일치.

**우회**: `docker volume rm <deploy>_op-geth-data` 후 재시도.

**근본 수정** (commit `0f453c3`, `local_network.go:600-640, 1107+`):
`os.Stat` 기반 probe 를 `docker volume inspect` + alpine helper container
를 이용한 volume 내부 `.genesis-hash` marker 읽기/쓰기 로 교체.
`volumeExists`, `readGenesisHashFromVolume`, `writeGenesisHashToVolume`
헬퍼 세 개 추가. 마커가 없거나 일치하지 않으면 `resetOpGethVolume` 을
호출해 chaindata 초기화.

**상태**: 코드 수정 완료. Runtime 재현 확인은 Bug #7 이 orchestrator 를
앞단에서 차단하고 있어 다음 세션으로 이월.

## Bug #6 — DRB-node 이미지 leader hostname 하드코딩 + volume 잔존 key

Bug #4 수정 후 규제러가 env init 통과하자마자 드러난 **두 개의 독립 sub-bug**.

### 6a — Hostname `leadernode` 하드코딩 (Workaround: network alias)

**증상**: Regular 로그에 `Leader multiaddress: /dns/leadernode/tcp/9600/...`
로 찍히고 dial 실패 (`no good addresses`). template 은
`LEADER_IP=drb-leader` 를 세팅했고 env 도 동일하게 들어감 — 그럼에도
multiaddr 에 `leadernode` 가 박힘.

**근본 원인**: `tokamaknetwork/drb-node:sha-8c37f63` 바이너리에 format
string 이 하드코딩 (확인: `strings /app/main | grep leadernode`):

```
/dns/leadernode/tcp/%s/p2p/%s
```

Upstream 현 main (`libp2putils/libp2p_client.go:201`) 은 이미 동적 `%s`
(= `leaderIP` 파라미터) 로 수정됨. **현재 사용 이미지는 LEADER_IP env 지원
이전 버전**. env 를 어떻게 세팅해도 무의미.

**수정** (commit `0f453c3` Fix A, `templates/local-compose.yml.tmpl:437-440`):
이미지 교체 대신 docker-compose `drb-leader` 서비스에 network alias
추가:

```yaml
drb-leader:
    ...
    networks:
      default:
        aliases:
          - leadernode
```

**검증**: regular 컨테이너에서 `getent hosts leadernode` 가 drb-leader
서비스 IP (예: 172.19.0.11) 로 resolve 됨을 확인. 이로써 Bug #6a 는 E2E
기준으로 ✅.

**후속 권장**: DRB-node 이미지를 LEADER_IP env 지원 버전으로 업그레이드
하여 alias workaround 를 걷어내는 것이 깔끔함 (별개 작업).

### 6b — Leader PeerID mismatch (image-default key override, Bootstrap 순서)

**증상**: regular 가 dial 하는 leader PeerID (`12D3KooWBfCV5...`) 와 leader
컨테이너가 실제로 보고하는 PeerID (`12D3KooWNocQ8qXBk...`) 가 불일치.

**근본 원인**: trh-sdk `drb_peer_id.go:18-49` 가 mnemonic 기반 결정론적
PeerID 를 계산해 template `{{ $.DRBLeaderPeerID }}` 에 바인딩 + volume
`drb-leader-keys:/app/static-key/leadernode.bin` 에 private key 를 주입.
하지만 orchestrator 순서가:

1. `docker compose up -d` — leader 컨테이너 부팅 (**빈 volume 이면
   이미지 레이어의 default `leadernode.bin` 을 volume 에 복사** → leader 는
   default key 로드)
2. `BootstrapDRBPeerIDFiles()` — 계산한 private key 를
   `leadernode.bin` 에 override write (**이미 부팅된 leader 는 모름**)

결과: leader 는 image-default key 로 계속 실행, regular 는 template 에
박힌 새 PeerID 로 dial → 불일치.

**확인**:
```bash
docker run --rm -v <deployId>_drb-leader-keys:/k alpine ls -la /k
# -> leadernode.bin, Jan 6 timestamp (= image layer 시점)
```

Jan 6 타임스탬프는 **이미지 빌드 시점의 파일이 빈 named volume 으로
복사되었음**을 증명 (Docker named volume 최초 마운트 시 이미지 경로 콘텐츠
자동 복사 동작).

**수정** (commit `0f453c3` Fix B, `local_network.go:1074-1086`):
`BootstrapDRBPeerIDFiles` 가 새 key 를 쓴 후 **leader + regular-N 컨테이너를
`docker compose restart` 로 재기동**. 재기동 시에는 volume 에 이미 새 key
가 있으므로 default key 로드 경로가 발동하지 않음.

```go
restartArgs := []string{"compose", "-f", composePath, "restart", "drb-leader"}
for _, regular := range accounts.Regulars {
    restartArgs = append(restartArgs, fmt.Sprintf("drb-regular-%d", regular.Index))
}
```

**Runtime 확인** (2026-04-28): ✅

`trh-backend:latest` 이미지가 `0f453c3` 이전 버전이어서 `BootstrapDRBPeerIDFiles` 가 호출되지 않음 — volume 내 `leadernode.bin` 타임스탬프 `Jan 6` 유지로 확인. 수동 bootstrap 으로 해결:

```bash
# 1. trh-sdk 소스에서 bootstrap 바이너리 빌드
cd /tmp/drb_bootstrap
cat > main.go << 'EOF'
package main
import (
    "context"; "fmt"; "os"
    thanos "github.com/tokamak-network/trh-sdk/pkg/stacks/thanos"
)
func main() {
    mnemonic := os.Args[1]; projectName := os.Args[2]
    accounts, err := thanos.DeriveDRBAccounts(mnemonic)
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
    fmt.Printf("Leader PeerID: %s\n", accounts.LeaderPeerID)
    if err := thanos.BootstrapDRBPeerIDFiles(context.Background(), projectName, accounts); err != nil {
        fmt.Fprintln(os.Stderr, err); os.Exit(1)
    }
    fmt.Println("Bootstrap complete")
}
EOF
go mod init drb_bootstrap
go mod edit -replace github.com/tokamak-network/trh-sdk=/path/to/trh-sdk
go mod tidy
go build -o drb_bootstrap .

# 2. 실행 (mnemonic + deploymentId)
./drb_bootstrap "mnemonic words here" "<deployment-uuid>"

# 3. leader 재시작
docker restart <deployId>-drb-leader-1
```

**검증**: `docker logs <deployId>-drb-leader-1 | grep "PeerID"` → template 에 바인딩된 PeerID 와 일치.

**주의**: regular 노드는 `regularnode.bin` 을 사용하지 않고 매 재시작마다 랜덤 키를 생성. 하지만 DRB 프로토콜은 EOA 서명 기반 registration 이므로 peer ID 변경이 프로토콜에 영향 없음 — leader 가 재등록 수락.

**근본 해결**: `tokamaknetwork/trh-backend` 이미지 재빌드 (trh-sdk `0f453c3` 포함) 로 자동 bootstrap + restart 보장.

### 의존 관계

6a 와 6b 는 **독립 원인**이지만 6a 가 dial 단계에서 먼저 실패하므로 6a
미해결 시 6b 는 시각적으로 드러나지 않음. 이번 세션 해결 순서: **6a (alias)
→ 6b (restart)** 순으로 수정 적용.

## Bug #7 — `readBedrockDeployConfigTemplate` 레거시 경로 강제 (코드 수정, E2E 미확인)

**증상**: Bug #5/#6 수정 직후 orchestrateDRBOperators 진입 시점에
`failed to read deployment contracts: open
<deploy>/tokamak-thanos/packages/tokamak/contracts-bedrock/scripts/deploy-config.json:
no such file or directory`.

**근본 원인** (Bug #1 과 동일 class — 2026-04-16 generate-genesis
Foundry→tokamak-deployer v0.0.5 리팩토링이 부분 이행되면서 발생한 레거시
경로 잔존):

- `pkg/stacks/thanos/shutdown.go:273-302` 의 `readDeploymentContracts`
  가 `readBedrockDeployConfigTemplate` 를 호출
- `readBedrockDeployConfigTemplate` (`shutdown.go:311-312` 근방) 은
  `<deploy>/tokamak-thanos/packages/tokamak/contracts-bedrock/scripts/deploy-config.json`
  을 하드코딩해서 읽음
- 그러나 새 tokamak-deployer 는 이 경로에 deploy-config.json 을 **쓰지
  않음** (새 deployer 는 `<deploy>/deploy-config.json` 또는 내부 temp 경로만
  사용)

**결과**: DRB operator orchestration (drb-leader, drb-regular-N 컨테이너
생성 이후 AnchorStateRegistry 초기화, operator activate 호출) 가 호출 전에
실패 → 이번 세션에서 Fix B (restart) 와 Fix C (volume reinit) 의 runtime
경로가 한 번도 발동하지 못함.

**수정** (commit `4c3e33b`, `shutdown.go:304-341`): 해결 후보 1번 (Bug #1
동일 패턴) 채택.

```go
candidates := []string{
    filepath.Join(s.deploymentPath, "deploy-config.json"), // new tokamak-deployer
}
if bedrockPath, err := s.getBedrockPath(); err == nil {
    candidates = append(candidates,
        filepath.Join(bedrockPath, "scripts", "deploy-config.json")) // legacy Foundry
}
for _, filePath := range candidates {
    if !utils.CheckFileExists(filePath) { continue }
    // read + json.Unmarshal → return config
}
```

두 write-site (`deploy_contracts.go:143` 의 new + legacy Foundry) 가
같은 `types.DeployConfigTemplate` 구조체를 직렬화하므로 스키마 변환
불필요. new path 우선 채택 + legacy path 폴백으로 이전 Foundry 시대 체인의
shutdown 워크플로우도 그대로 작동.

**단위 테스트** (`shutdown_test.go`, 4개):
- `NewPath`: legacy 부재 + new 존재 → new 로드 성공
- `LegacyFallback`: new 부재 + legacy 존재 → legacy 로드 성공
- `NewPathPrecedence`: 둘 다 존재 → new 우선 (stale legacy 사용 방지)
- `NoneFound`: 둘 다 부재 → 명확한 에러 메시지

**부차 영향 — 잠복 버그 노출**: `generateLocalComposeFile`
(`local_network.go:252-256`) 은 `readDeploymentContracts()` 실패 시 warning
만 남기고 빈 `types.Contracts{}` 로 진행해 왔음. 이는 Bug #7 이 살아 있는
동안 **compose 파일이 빈 컨트랙트 주소로 템플릿 치환되고도 조용히 통과**
하는 상태였음을 의미. 이번 fix 이후 실제 주소가 주입되므로 이전과
구성이 달라진 것처럼 보일 수 있음 (실제로는 항상 이 주소여야 했음).
과거 로그에서 "compose 는 문제없이 생성됐는데 왜 contract address 가
비어있지?" 같은 관찰이 있었다면 이 원인이었을 가능성.

**E2E runtime 확인 (2026-04-18 세션)**:
- **Fix #7 verified ✅** — resume 시 `readDeploymentContracts` 가
  AnchorStateRegistryProxy 필드 부재 에러로 실패하는 지점에 도달했다는 것은
  그 앞 단계의 `readBedrockDeployConfigTemplate` 가 `deploy-config.json`
  을 정상적으로 읽었음을 의미 (Fix #7 가 없다면 "deploy config file not
  found" 에러로 먼저 실패). 다른 직접 마커는 없지만 간접 증명 완료.
- **Fix #5 verified ✅** — backend 로그에 `op-geth volume already
  initialized with matching genesis, skipping init` 기록. 준비된 stale
  volume (`.genesis-hash` marker 존재, hash 일치) 시나리오에서 skip-init
  branch 가 정상 발동.
- **Fix #6b 미확인 ⚠️** — `orchestrateDRBOperators` 진입 전 Bug #8 이 차단.

## Bug #8 — Fault-proof 컨트랙트 미배포 (--fault-proof 플래그 미연결)

**증상** (2026-04-18 resume 시):
```
deployment failed: AnchorStateRegistryProxy address not found in
deployed contracts — cannot initialize genesis anchor state
```

**위치**: `local_network.go:163-164` — fault-proof path 의 anchor init
pre-check. `readDeploymentContracts()` 가 non-nil 리턴했지만 반환된
`types.Contracts.AnchorStateRegistryProxy` 가 빈 문자열.

**초기 가설 (wrong)**: tokamak-deployer 가 AnchorStateRegistryProxy 를
배포는 하지만 `deploy-output.json` 에 emit 하지 않음 — "반쪽 포팅" 산출물
incomplete 문제로 추정.

**실제 근본 원인**: tokamak-deployer 의 deploy-contracts CLI 에는
`--fault-proof` 플래그 자체가 등록되어 있지 않았다 (v0.0.5 까지).
따라서 `deployer.DeployConfig.EnableFaultProof` 는 항상 `false` 였고,
`contracts.go:526` 의 `if cfg.EnableFaultProof` gate 는 절대 true 가
될 수 없었음. Steps 27-32 (DisputeGameFactory + AnchorStateRegistry
배포) 가 **조용히 전체 skip** 되어 온 것.

즉 컨트랙트가 "배포되었는데 주소만 누락"이 아니라 **애초에 배포 자체가
실행되지 않았던 것**. `deploy-output.json` 에 주소가 없는 건 그래서 당연.

**Fix** (세 레이어):

| 레이어 | 변경 | 커밋 |
|--------|-------|-------|
| tokamak-thanos (producer CLI) | `cmd/tokamak-deployer/cmd/deploy_contracts.go` 에 `--fault-proof` bool 플래그 등록 + `cfg.EnableFaultProof` 에 wire | `7af425cdf4` + anvil E2E 검증 `8b0473bf12` |
| trh-sdk (wiring) | `deployContractsOpts.EnableFaultProof` 추가; `runDeployContracts` 에서 flag pass; `TokamakDeployerVersion v0.0.5 → v0.0.6` | `f009dbc` + unit test `6c8da80` |
| trh-sdk (consumer 경로) | `readDeploymentContracts` searchPaths 에 `<deploymentPath>/deploy-output.json` 을 **최우선**으로 추가. 기존 `<contracts-bedrock>/deployments/<L1ChainID>-deploy.json` 은 `cloneSourcecode` 가 tokamak-thanos 레포에서 체크아웃하는 stale 파일이므로 읽힐 경우 새 주소를 shadow 함 | `2a688a8` |

**Producer-consumer 링크 격차 (세 번째 레이어의 존재 이유)**: Producer-side
fix 만으로는 부족함이 advisor 리뷰에서 확인됐다. 새 파이프라인은
`<deploymentPath>/deploy-output.json` 을 쓰지만, consumer 인
`readDeploymentContracts` 는 Foundry 시절 artifact 인
`<contracts-bedrock>/deployments/<L1ChainID>-deploy.json` 을 읽었다. 이 파일은
tokamak-thanos 레포에 체크인되어 있어 `cloneSourcecode` 직후 fresh 배포에도
이미 존재하고 (10 core addresses, no fault-proof), 새 파이프라인의 그 어떤 단계도
이 파일을 재작성하지 않는다. Bug #7 의 new-path-first 패턴과 동일하게
우선순위만 바꾸면 해결.

**검증 후 필요 작업**: DRB/fault-proof 스택은 **새 Sepolia 배포** 가 필요.
기존 실패 배포 디렉토리의 L1 컨트랙트들은 fault-proof 없이 배포되었으므로
DisputeGameFactory/AnchorStateRegistry 가 존재하지 않음 — re-deploy 외에 복구 경로 없음.

**분류**: Producer-side bug + consumer-side path mismatch. trh-sdk 단독 fix 로는
producer 문제 해결 불가 (upstream CLI 기능 자체가 빠짐). 단, producer fix 만으로
끝나지도 않음 — 새 산출물이 소비자에 닿는 경로까지 같이 고쳐야 함.

**Caller 범위 주의**: `readDeploymentContracts` 는 `local_network.go:163`
(anchor init 검증), `deploy_chain.go:523` (anchor 초기화 실행),
`aa_bridge.go:73` 등 다수 caller 가 공유. `setupSafeWallet`
(`register_candidate.go:465`) 은 직접 `<L1ChainID>-deploy.json` 를 읽고
`SystemOwnerSafe` 를 찾음 — 이 필드는 tokamak-deployer 의 `DeployOutput`
구조체에 아직 없어서 register-candidate 플로우에서는 여전히 legacy 경로에
의존. 해당 플로우를 새 경로로 전환하려면 추가 작업 필요.

**현재 Sepolia 검증에는 영향 없음**: trh-backend 의 4개 preset
(base/defi/gaming/full) 모두 `ChainDefaults.registerCandidate = false`
(`presets/service.go:78,117,157,197`). 따라서 이번 fresh 배포 검증에서
`setupSafeWallet` 은 fire 하지 않음. register-candidate 를 enable 한
별도 플로우에서만 잠재 이슈가 발생 — 별도 추적 필요.

## 증거 — 성공 지표 (Bug #4·#5·#6 해결되면 기대되는 마커)

Leader 노드의 1차 기동 시 아래 로그가 나오면 predeploy 연동은 이미 OK:

```
leader host created with PeerID: 12D3Koo...
Fetched current round from contract: 0
Fetched trialNum for round 0 from contract: 0
Current s_isInProcess value: 2
```

이 세 줄은 `0x4200000000000000000000000000000000000060` 의 CommitReveal2L2
predeploy 가 live L2 에서 호출 가능함을 의미.

## 관련 커밋·파일

- trh-sdk `50d0b39` — bug #1, #2, #3 fix (path + FuncMap + range scope)
- trh-sdk `3912799` — bug #4 fix (EOA_PRIVATE_KEY + LEADER_IP env 키 교정)
- trh-sdk `0f453c3` — bug #5 / #6a / #6b fix (volume reinit + alias + restart
  after bootstrap). Fix B/C runtime 확인은 Bug #7 로 이월
- trh-sdk `4c3e33b` — bug #7 fix (`readBedrockDeployConfigTemplate` new path
  precedence + legacy fallback) + 4 unit tests
- tokamak-thanos `7af425cdf4` — bug #8 producer fix (deploy-contracts
  `--fault-proof` flag wiring) + tag `tokamak-deployer/v0.0.6` (release with new
  binary) + anvil integration test `8b0473bf12`
- trh-sdk `f009dbc` / `6c8da80` / `2a688a8` — bug #8 wiring + consumer path fix
  (readDeploymentContracts prefers deploy-output.json)
- runtime 검증 세션 2026-04-18 19:04-19:09 UTC — Fix #5 log marker
  확인: `trh-backend` 컨테이너 로그의 `op-geth volume already initialized
  with matching genesis, skipping init` at 19:05:52.695Z
- trh-backend `f732a48` — deploy-infra step 레이블 AWS/local 분리
  (`DeployAWSInfraStep` + `DeployLocalInfraStep` + `GetDeployInfraStepName`)
- `pkg/stacks/thanos/local_network.go:250-280, 431, 590-640, 1074-1107+`
- `pkg/stacks/thanos/templates/local-compose.yml.tmpl:437-440, 441-484`
- `pkg/stacks/thanos/shutdown.go:273-312` — Bug #7 원인 지점
- DRB-node upstream `config/env.go:135-144`, `nodes/regular/handler.go:108`,
  `libp2putils/libp2p_client.go:201`
- DRB-node image `tokamaknetwork/drb-node:sha-8c37f63` — 구버전, Bug #6a
  원인
- trh-sdk plan handoff:
  [`docs/superpowers/plans/2026-04-18-drb-local-deploy-unblock.md`](https://github.com/tokamak-network/trh-sdk/blob/main/docs/superpowers/plans/2026-04-18-drb-local-deploy-unblock.md)
