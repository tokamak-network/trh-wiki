---
updated: 2026-05-08
tags: [troubleshooting, forge, genesis, tokamak-deployer]
sources: []
related:
  - "[[forge-l2genesis-silent-slow]]"
---


# forge L2Genesis: "expected address, found JSON object" revert

## 증상

`deploy-l1-contracts` 단계에서 tokamak-deployer 35 step이 모두 성공한 뒤 forge L2Genesis 실행 시 revert:

```
[forge] vm.parseJsonAddress: expected address, found JSON object
[forge] script failed: <empty revert data>
❌ Failed to run forge L2Genesis.s.sol
```

forge trace에서 마지막으로 처리된 키는 `$.implementations`:

```
├─ [0] VM::parseJsonAddress("<stringified JSON>", "$.implementations") [staticcall]
│   └─ ← [Revert] vm.parseJsonAddress: expected address, found JSON object
```

---

## 근본 원인

**tokamak-deployer v0.0.10**이 `deploy-output.json`에 `implementations` 키를 추가했다:

```json
{
  "l1ChainId": 11155111,
  "l2ChainId": 111551194428,
  "OptimismPortalProxy": "0x...",
  "SystemConfigProxy": "0x...",
  "implementations": {
    "OptimismPortal": "0x968aaf1A6010dc9d97A3dBA5d176dE7671F4abEA",
    "SystemConfig": "0x531aC70DCa1934E8Ed870FBa52326f300C876480"
  }
}
```

`genesis_prep.go:writeAddressesOnly()`가 staged 주소 파일을 생성할 때 `l1ChainId`/`l2ChainId`만 제거하고 `implementations` (중첩 JSON 오브젝트)는 그대로 통과시켰다.

forge L2Genesis.s.sol은 `CONTRACT_ADDRESSES_PATH` 파일의 **모든 키**에 대해 `vm.parseJsonAddress`를 호출한다. `implementations` 값이 `string`이 아닌 `object`이므로 revert.

---

## 수정 (2026-05-08)

**파일:** `trh-sdk/pkg/stacks/thanos/genesis_prep.go`
**커밋:** `c170452`

`writeAddressesOnly` 필터링 로직을 값의 첫 바이트로 확장:

```go
// Before: only stripped l1ChainId / l2ChainId
if k == "l1ChainId" || k == "l2ChainId" {
    continue
}

// After: skip any value that is not an address string
first := strings.TrimSpace(string(v))
if len(first) == 0 || first[0] == '{' || first[0] == '[' || first[0] >= '0' && first[0] <= '9' {
    continue
}
```

- `{` 로 시작 → JSON 오브젝트 (예: `implementations`)
- `[` 로 시작 → JSON 배열
- `0-9` 로 시작 → JSON 숫자 (예: `l1ChainId`, `l2ChainId`)

이 방식은 tokamak-deployer가 앞으로 추가할 비-주소 필드에도 자동 대응한다.

---

## 관련 파일

| 파일 | 역할 |
|------|------|
| `trh-sdk/pkg/stacks/thanos/genesis_prep.go` | `writeAddressesOnly` 필터 로직 |
| `trh-sdk/pkg/stacks/thanos/genesis_prep_test.go` | 회귀 방지 테스트 |

---

## 유사 버그

- [[forge-l2genesis-silent-slow]] — 같은 함수의 logging/streaming 버그 (별개 문제)
