---
updated: 2026-04-09
sources:
  - raw/decisions/PRD-CrossTrade-TRH-Integration-v2.1.md
related:
  - "[[trh-sdk]]"
  - "[[deposit-tx]]"
  - "[[cross-trade]]"
tags: [decision]
---

# Decision: abigen vs Manual Calldata

**결정:** OptimismPortal 직접 L1 호출에는 **abigen 바인딩**, L2 calldata (Deposit Tx _data 필드)에는 **abi.Pack** 사용.

---

## 두 패턴 비교

### abigen 바인딩

`abigen` 도구로 ABI에서 Go 타입 안전 바인딩을 자동 생성한다:

```go
// 생성된 코드: abis/OptimismPortal.go
portal, err := abis.NewOptimismPortal(portalAddr, client)
tx, err := portal.DepositTransaction(opts, _to, _value, _gasLimit, _isCreation, _data)
```

**장점**: 컴파일 타임 타입 체크, IDE 자동완성, 파라미터 누락/순서 오류 방지

### abi.Pack (런타임 인코딩)

ABI JSON을 런타임에 파싱하여 calldata를 직접 인코딩한다:

```go
abi, _ := abi.JSON(strings.NewReader(CrossTradeABI))
data, _ := abi.Pack("initialize", crossDomainMessenger, nativeToken)
```

**장점**: ABI 파일 없이 동작, 함수 선택자 포함 calldata 직접 생성

---

## 어떤 상황에서 어떤 패턴을 사용하나

| 상황 | 패턴 | 이유 |
|------|------|------|
| OptimismPortal.depositTransaction() L1 직접 호출 | **abigen** | 5개 파라미터 타입 안전성 필수. 잘못된 인코딩은 L2에서 조용히 실패 |
| L2 calldata (Deposit Tx `_data` 필드) | **abi.Pack** | L2 ABI가 배포 시 런타임에 필요. `drb_genesis.go` 기존 패턴 |
| Backend L1 setChainInfo | **abigen** | L1CrossTradeProxy, L2toL2CrossTradeL1 — 직접 L1 호출 |

---

## SDK 기존 선례

| 파일 | 패턴 | 용도 |
|------|------|------|
| `trh-sdk/abis/TON.go` | abigen | TON 토큰 직접 호출 |
| `trh-sdk/abis/L1ContractVerification.go` | abigen | L1 검증 컨트랙트 |
| `trh-sdk/pkg/stacks/thanos/drb_genesis.go` | abi.Pack | DRB L2 컨트랙트 calldata |
| `trh-sdk/pkg/stacks/thanos/deploy_chain.go` | bind.WaitMined | L1 tx receipt 대기 |

---

## 수동 keccak256 selector 계산을 쓰지 않는 이유

```go
// 나쁜 패턴 — 이렇게 하지 않는다
selector := crypto.Keccak256([]byte("depositTransaction(address,uint256,uint64,bool,bytes)"))[:4]
data := append(selector, abiEncode(args...)...)
```

- 함수 서명 오타가 런타임까지 감지되지 않음
- bytes 패킹 오류가 조용히 잘못된 트랜잭션 생성
- 5개 파라미터 타입 매핑을 수동으로 맞춰야 함

---

## abigen 실행 방법

```bash
# trh-sdk/abis/ 디렉토리에서
abigen --abi OptimismPortal.abi.json \
       --pkg abis \
       --type OptimismPortal \
       --out abis/OptimismPortal.go
```

ABI 파일 소스: OP Stack `contracts-bedrock` artifacts (L2 배포 시 이미 사용 중).
