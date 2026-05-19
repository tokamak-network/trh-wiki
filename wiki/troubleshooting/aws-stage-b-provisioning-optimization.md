---

updated: 2026-05-19
sources: []
related:
  - "[[elb-dns-propagation-delay]]"
tags: [troubleshooting]
---
# AWS Stage B 프로비저닝 대기 최적화

## 배경

ELB DNS 전파 지연 fix(ca84863, [[elb-dns-propagation-delay]]) 이후에도 Stage B(EKS 체인 노드 배포)는 여전히 ~11분 이상 소요되었다. 원인은 DNS 지연이 아니라 ALB 프로비저닝 자체의 대기 시간이었다.

전체 배포 시간: 최적화 전 **41분**, 목표 **≤30분**.

## 발견된 아키텍처 사실

- **op-geth RPC entrypoint는 ALB**(NLB가 아님). Kubernetes Ingress → AWS ALB Controller → ALB 생성.
- `WaitForIngressAddress`는 ALB Controller가 hostname을 stamping하는 시점(t≈30-90s)에 반환하지만, 실제 트래픽은 ALB target health 달성 후에야 가능하다.
- **L1 init 함수들은 L2 RPC에 의존하지 않는다** — `initSystemConfig`, `initL1CrossDomainMessenger`, `initOptimismPortal`, `initL2OutputOracle`, `initDisputeGameFactory`, `initOptimismPortal2` 모두 `L1RPCURL`만 사용함을 코드로 확인. 이 사실이 P3 병렬화의 핵심 전제다.
- `initDisputeGameFactory`는 게임 구현체 등록만 하고 게임을 생성하지 않는다. 따라서 DGF init 완료 후 `initGenesisAnchorState`(L2 RPC 필요) 실행이 안전하다.

## 적용한 최적화 4종

### P0 — op-geth readinessProbe 튜닝

**파일**: `tokamak-thanos-stack/charts/thanos-stack/templates/op-geth-statefulset.yaml`

```yaml
# Before
readinessProbe:
  initialDelaySeconds: 60
  periodSeconds: 30
  failureThreshold: 200

# After
readinessProbe:
  initialDelaySeconds: 10   # op-geth는 보통 5-20s 내 8545 오픈
  periodSeconds: 5
  failureThreshold: 60      # 5s × 60 = 300s 총 grace
```

livenessProbe는 변경하지 않았다(initialDelaySeconds: 600 유지). sync 중 재시작 방지가 liveness의 목적이기 때문.

**절감**: ~60-90s

### P1 — ALB Ingress Health Check 튜닝

**파일**: `tokamak-thanos-stack/terraform/thanos-stack/scripts/generate-thanos-stack-values.sh`

op-geth ingress annotation 블록에 추가:

```yaml
alb.ingress.kubernetes.io/healthcheck-interval-seconds: '10'   # default 30
alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
alb.ingress.kubernetes.io/healthy-threshold-count: '2'         # default 5
alb.ingress.kubernetes.io/success-codes: '200-499'             # critical!
alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=10
```

**`success-codes: '200-499'`가 필수**: op-geth는 GET `/`에 4xx를 반환한다. 기본 matcher(200-399)를 그대로 두면 target이 영구 unhealthy 상태로 남는다.

ALB healthy 대기 시간: default 30s × 5회 = 150s → 10s × 2회 = **20s**

**절감**: ~60-120s

### P2 — ELB NS 캐시 + Context 전파

**파일**: `trh-sdk/pkg/utils/utils.go`, `pkg/stacks/thanos/uptime_service.go`

1. `sync.Map` 기반 NS 캐시(TTL 5분) 추가 — 5초 폴링 시 매 호출마다 `LookupNS` + `LookupHost`를 수행하던 문제 해결:

```go
var elbNSCache sync.Map
type elbNSCacheEntry struct {
    nsAddr    string
    expiresAt time.Time
}
```

2. `IsURLReachableCtx(ctx, url)` 추가 — 호출자 context 취소/타임아웃 전파.
3. `uptime_service.go` 폴링 루프에서 `IsURLReachableCtx(ctx, ...)` 사용.

**절감**: ~30-60s (폴링 100회 × NS 조회 100-500ms 누적 제거)

### P3 — Ingress 대기 ↔ L1 Contract Init 병렬화

**파일**: `trh-sdk/pkg/stacks/thanos/deploy_chain.go`

기존 직렬 흐름:
```
WaitForIngressAddress (~3-5min)
  → L1 init (SystemConfig → CDM → L2OO 또는 DGF+OP2)
  → FP only: initGenesisAnchorState
```

변경 후 (`errgroup.WithContext`):
```
┌─ WaitForIngressAddress (최대 45min) ─┐
│                                       │ ← 병렬
└─ L1 init (SystemConfig → CDM → ...) ─┘
           ↓ eg.Wait()
    l2RPCUrl = "http://" + ingressAddr
    FP only: initGenesisAnchorState (L2 RPC 필요)
```

Nonce 충돌 없음: ingress wait goroutine은 L1 tx를 전송하지 않는다.

**절감**:
- L2OO path: ~1-2min
- FP path: ~5-8min (DGF+OP2 init이 ingress wait와 완전히 겹침)

## 커밋 정보

| 레포 | 커밋 | 항목 |
|------|------|------|
| tokamak-thanos-stack | `c2e8354` | P0 + P1 |
| trh-sdk | `e4765c8` | P2 + P3 + poll 5s + sleep 제거 |

## 누적 절감 추정

| 최적화 | 절감 |
|--------|------|
| poll 15s→5s + 30s sleep 제거 | ~30s |
| P0 probe tuning | ~60-90s |
| P1 ALB annotation | ~60-120s |
| P2 NS cache | ~30-60s |
| P3 parallelization (L2OO) | ~1-2min |
| P3 parallelization (FP) | ~5-8min |

**추정 결과**: L2OO path ~35분, FP path ~29.5분 (기존 41분)

## 검증 방법

- ALB target health 도달 시간: `aws elbv2 describe-target-health --target-group-arn $TG`
- NS 캐시 효과: `utils.go` 로그에서 첫 번째만 `LookupNS` 수행, 이후 캐시 사용 확인
- P3 효과: Stage B 로그에서 "Waiting for ingress address"와 "Initializing SystemConfig" 타임스탬프 겹침 확인
