---
updated: 2026-04-18
sources:
  - commit 50d0b39 (trh-sdk main)
related:
  - "[[deploy-methods-comparison]]"
  - "[[drb-project]]"
  - "[[drb-node]]"
  - "[[l2-deploy-local]]"
tags: [troubleshooting, drb, local-compose, gaming-preset]
---

# DRB Gaming Preset 로컬 배포 — 5개 경로·템플릿 버그

2026-04-17 preset resume-deploy (gaming + USDT + fault-proof ON) 시 순차적으로
드러난 5개 독립 버그. 1-4 는 trh-sdk main (50d0b39) 에서 수정. 5 는 미해결.

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

## Bug #5 — op-geth volume stale (미해결)

**증상**: resume 재시도 시 op-node 가
`expected L2 genesis hash to match L2 block at genesis block number 0:
<hash_in_geth_chaindata> <> <hash_in_new_genesis.json>` 로 crash.

**근본 원인**: 1차 배포 실패 후 2차 resume 에서 새 L2 genesis 가 생성되지만
op-geth 가 기존 volume 의 chaindata 를 재사용. `local_network.go:600-622` 의
hash 기반 재초기화 로직이 있으나 **resume 경로에서 발동하지 않는 조건**.

**우회**: `docker volume rm <deploy>_op-geth-data` 후 재시도.

**근본 해결 후보**:
- resume 진입 시점에 무조건 genesis hash 를 계산해서 `.genesis-hash` 와 비교
- `op-geth-data` volume 도 `ConfigVolume` 처럼 deployment ID 로 suffix

## Bug #6 — DRB-node 이미지 leader hostname 하드코딩 + volume 잔존 key (미해결)

Bug #4 수정 후 규제러가 env init 통과하자마자 드러난 **두 개의 sub-bug**.

### 6a — Hostname `leadernode` 하드코딩

**증상**: Regular 로그에 `Leader multiaddress: /dns/leadernode/tcp/9600/...`
로 찍히고 dial 실패 (`no good addresses`). template 은
`LEADER_IP=drb-leader` 를 세팅했고 env 도 동일하게 들어감 — 그럼에도
multiaddr 에 `leadernode` 가 박힘.

**근본 원인**: `tokamaknetwork/drb-node:sha-8c37f63` 바이너리에 format
string 이 하드코딩:

```
/dns/leadernode/tcp/%s/p2p/%s
```

Upstream 현 main (`libp2putils/libp2p_client.go:201`) 은 이미 동적 `%s`
(= `leaderIP` 파라미터) 로 수정됨. **현재 사용 이미지는 LEADER_IP env 지원
이전 버전**. env 를 어떻게 세팅해도 무의미.

**해결 후보**:
- DRB-node 이미지를 upstream 최신 tag 로 업데이트 (권장)
- 또는 docker-compose 에서 service 별칭을 `leadernode` 로 추가 (workaround)

### 6b — Leader PeerID mismatch (volume stale)

**증상**: regular 가 dial 하는 leader PeerID (`12D3KooWBfCV5...`) 와 leader
컨테이너가 실제로 보고하는 PeerID (`12D3KooWNocQ8qXBk...`) 가 불일치.

**근본 원인**: trh-sdk `drb_peer_id.go:18-49` 가 mnemonic 기반 결정론적
PeerID 를 계산해 template `{{ $.DRBLeaderPeerID }}` 에 바인딩 + volume
`drb-leader-keys:/app/static-key/leadernode.bin` 에 private key 를 주입.
하지만 volume 이 persist — 이전 배포의 `leadernode.bin` (68B) 이 남아
있으면 leader 컨테이너가 bootup 시 **구 key 로드** → 구 PeerID 노출. 한편
template 은 새 계산값을 박아넣어 불일치.

**확인**:
```bash
docker run --rm -v <deployId>_drb-leader-keys:/k alpine ls -la /k
# -> 구 leadernode.bin (예: Jan 6 timestamp) 이 남아 있음
```

**해결 후보**:
- `BootstrapDRBPeerIDFiles()` 가 항상 overwrite 하도록 보장 (truncate +
  write)
- 또는 배포 시작 시 `drb-*-keys` volume 무조건 `docker volume rm`

### 의존 관계

6a 와 6b 는 **독립 원인**이지만 6a 가 dial 단계에서 먼저 실패하므로 6a
미해결 시 6b 는 시각적으로 드러나지 않음. 해결 순서: **6a 먼저 (이미지
업그레이드)** → 6b 검증 → 필요 시 6b fix.

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
- `pkg/stacks/thanos/local_network.go:250-280, 431, 590-640`
- `pkg/stacks/thanos/templates/local-compose.yml.tmpl:441-484`
- DRB-node upstream `config/env.go:135-144`, `nodes/regular/handler.go:108`
- DRB-node image `tokamaknetwork/drb-node:sha-8c37f63` — 구버전, Bug #6a
  원인
