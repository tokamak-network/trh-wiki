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

## Bug #4 — Regular 노드 `PORT` env 이름 (확정 전)

**증상**: 템플릿에 `PORT=9601` 를 세팅해도 DRB-node 가
`PORT not set in environment variables` 로 crash.

**현재 상태**: Phase 2 조사 필요. DRB-node source repo 에서 실제 env 키를
확인해야 함. 후보: `REGULAR_PORT`, `NODE_PORT`, `P2P_PORT`, `LIBP2P_PORT`.

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

## 증거 — 성공 지표 (Bug #4·#5 해결되면 기대되는 마커)

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

- trh-sdk `50d0b39` — bug #1, #2, #3, #4(미검증) fix
- `pkg/stacks/thanos/local_network.go:250-280, 431, 590-640`
- `pkg/stacks/thanos/templates/local-compose.yml.tmpl:441-484`
