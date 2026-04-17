---
updated: 2026-04-18
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
수정. 7 은 commit `4c3e33b` 에서 수정. **Bug #8 은 미해결** — tokamak-deployer
output 에 `AnchorStateRegistryProxy` 가 포함되지 않음.

## 현재 상태 요약

| Bug | 증상 요약 | 코드 수정 | Runtime 확인 |
|---|---|---|---|
| #1 | genesis/rollup 경로 불일치 | `50d0b39` | ✅ |
| #2 | `add` 템플릿 함수 미등록 | `50d0b39` | ✅ |
| #3 | range 내부 root-scope 접근 실패 | `50d0b39` | ✅ |
| #4 | Regular 노드 env 키 이름 | `3912799` | ✅ |
| #5 | op-geth volume stale (host 경로 probe 오류) | `0f453c3` Fix C | ✅ **2026-04-18 verified** (`skipping init` branch) |
| #6a | Hostname `leadernode` 하드코딩 | `0f453c3` Fix A (alias) | ✅ DNS 해결 확인 |
| #6b | Leader PeerID mismatch (image-default key) | `0f453c3` Fix B (restart) | ⚠️ 미확인 (Bug #8 로 차단) |
| #7 | `readBedrockDeployConfigTemplate` 레거시 경로 | `4c3e33b` (new-path-first + legacy fallback) | ✅ **2026-04-18 verified** (간접: anchor init 도달) |
| #8 | `AnchorStateRegistryProxy` 주소 미출력 | **미해결** (producer-side fix 필요) | ❌ 차단 중 |

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

**상태**: 코드 수정 완료. Runtime 재현 확인은 Bug #7 이 orchestrator 를
앞단에서 차단하고 있어 다음 세션으로 이월. 다음 세션에서는 leader 로그의
`leader host created with PeerID: 12D3Koo...` 값이 template 에 바인딩된
값과 일치함을 확인해야 함.

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

## Bug #8 — `AnchorStateRegistryProxy` 주소 미출력 (미해결)

**증상** (2026-04-18 resume 시):
```
deployment failed: AnchorStateRegistryProxy address not found in
deployed contracts — cannot initialize genesis anchor state
```

**위치**: `local_network.go:163-164` — fault-proof path 의 anchor init
pre-check. `readDeploymentContracts()` 가 non-nil 리턴했지만 반환된
`types.Contracts.AnchorStateRegistryProxy` 가 빈 문자열.

**근본 원인**: tokamak-deployer 의 `deploy-output.json` (그리고 Foundry
layer 의 `11155111-deploy.json`) 모두 10개 core L1 주소만 기록하고
`AnchorStateRegistryProxy` 필드가 전혀 없음. 이는 `deploy-methods-comparison`
에 이미 기록된 "반쪽 포팅" 상태의 결과:

> tokamak-deployer v0.0.5 fault-proof 지원은 "반쪽 포팅":
> DisputeGameFactoryProxy + AnchorStateRegistryProxy 의 deploy + plain
> upgrade 까지만. initialize/setImplementation/Safe wallet 실행 은 여전히
> forge 경로.

즉 deployer 는 AnchorStateRegistryProxy 를 **배포는 하지만** 주소를
`deploy-output.json` 에 emit 하지 않음. 별도 forge 스크립트가 돌아서
initialize 하는데 그 결과 주소도 어디에도 persist 되지 않음.

**분류**: Bug #1/#7 과 동급 class (new deployer 산출 incomplete) 이지만
fix 위치는 **producer-side (tokamak-deployer)** — 경로 재매핑만으로는
해결 불가. 주소를 찾아 output 파일에 쓰는 upstream 변경이 필요.

**해결 후보**:
1. tokamak-deployer 에 `AnchorStateRegistryProxy`·`DisputeGameFactoryProxy`
   등 fault-proof 관련 address 들을 `deploy-output.json` 에 추가 출력
2. 또는 trh-sdk 에서 배포 직후 L1 RPC 로 `DisputeGameFactoryProxy.anchorStateRegistry()`
   를 직접 조회해 AnchorStateRegistryProxy 를 얻고 별도 파일에 저장
3. 또는 SystemConfig 의 공개 메서드로 체인에서 직접 읽기 (가능 여부 확인 필요)

**다음 세션 작업**: Bug #8 을 해결해야 Fix #6b 의 runtime 검증이 가능.
단, Fix #6b 의 코드 경로는 advisor-reviewed + structurally-simple 이므로
Fix #1/#7 패턴 매치로 high confidence. E2E 필수성은 낮음.

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
- Bug #8 — 미해결, tokamak-deployer producer-side 수정 필요. 관련 레퍼런스:
  [[deploy-methods-comparison]] 의 "반쪽 포팅" 섹션
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
