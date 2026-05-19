# CrossTrade L2 Deposit Verification Timeout

## 증상

`DeployCrossTradeLocal` 실행 중 step 3에서 타임아웃:

```
step 3 L2 verification failed: deposit call effect not verified at 0x... after 120s
```

steps 1-2는 각각 85-109s에 성공했으나 step 3이 120s 한계를 초과.

## 근본 원인

**`sequencer_l1_confs: 5`** — op-node가 L1 블록의 deposit을 L2에 포함하기 전에 5개 L1 블록 확인을 기다리는 안전 설정.

```
tokamak-thanos-stack/charts/thanos-stack/values.yaml
op_node.env.sequencer_l1_confs: 5
```

### 지연 구조

| 단계 | 시간 |
|------|------|
| L1 tx → L1 receipt (1 L1 블록) | ~10s |
| op-node: deposit L1 블록 +5 confirmations 대기 | 5 × 12s = 60s |
| L2 블록 생산 | ~2s |
| **이론적 최소** | **~72s** |

실제 관측값 85-123s:
- L1 블록 시간 분산 (10-14s)
- op-node의 Alchemy RPC 폴링 레이턴시 (AWS ap-northeast-2 → Alchemy)
- cross-trade 배포 중 trh-backend가 동일 Alchemy API 키 동시 사용 → 일시적 rate limiting

### 검증 방법

```bash
# 현재 L2 L1 origin lag 측정
L2_L1_ORIGIN=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x4200000000000000000000000000000000000015","data":"0x8381f58a"},"latest"],"id":1}' \
  $L2_RPC | python3 -c "import json,sys; print(int(json.load(sys.stdin)['result'],16))")

L1_LATEST=$(curl -s -X POST ... $L1_RPC | python3 -c "...")

echo "Lag: $((L1_LATEST - L2_L1_ORIGIN)) blocks = $(( (L1_LATEST - L2_L1_ORIGIN) * 12 ))s"
# 정상: 5-8 blocks = 60-96s
```

## 해결책

`waitForContractCode`와 `verifyDepositCallEffect` 타임아웃을 120s(60 attempts) → 300s(150 attempts)로 증가.

**커밋**: trh-sdk `5bf42c5`

## 변경 파일

- `pkg/stacks/thanos/cross_trade_local.go`: 두 함수 모두 `60 → 150` attempts

## 대안 고려

`sequencer_l1_confs`를 1-2로 줄이면 지연이 12-24s로 단축되나, L1 reorg 시 sequencer 불안정 위험이 있어 채택하지 않음. testnet이라도 설정은 유지.
