# ELB DNS Propagation Delay (12-minute bottleneck)

## 증상

AWS EKS 배포 중 두 구간에서 총 ~12분의 불필요한 대기가 발생:

- **Phase 1 (~8분)**: `initGenesisAnchorState`에서 op-geth ELB URL로 `BlockByNumber(0)` 호출 → `no such host` 반복
- **Phase 2 (~4분)**: `uptime_service.go`에서 `IsURLReachable` HTTP 폴링 → `no such host` 반복

## 근본 원인

AWS ELB 생성 시 Route53에는 즉시 등록되지만, 공개 DNS 리졸버(8.8.8.8, 1.1.1.1, Docker 내부 127.0.0.11)는 이 레코드를 5-10분 동안 캐시에서 보지 못한다.

trh-backend는 Docker 컨테이너 내부에서 실행되므로 Docker DNS(127.0.0.11)를 사용 → 공개 DNS 전파 지연에 그대로 노출된다.

```
Docker 컨테이너 DNS(127.0.0.11)
  → 호스트 Mac 업스트림 리졸버
  → 공개 DNS (캐시 TTL: 5-10분)
     ↳ NOT FOUND (레코드는 Route53에 있지만 전파 안됨)

권위 DNS (Route53 ns-XXX.awsdns-XX.com)
  → 즉시 A 레코드 반환 ← 이쪽을 직접 쿼리해야 함
```

## 해결책

`*.elb.amazonaws.com` 호스트명에 대해 권위 NS를 동적으로 조회 후 직접 쿼리하는 커스텀 `net.Resolver`를 사용.

```
1. net.DefaultResolver.LookupNS("ap-northeast-2.elb.amazonaws.com")
   → ns-XXX.awsdns-XX.com (안정적, 공개 DNS에 캐시됨)
2. net.DefaultResolver.LookupHost("ns-XXX.awsdns-XX.com")
   → 실제 IP
3. &net.Resolver{Dial: UDP to NS IP:53}로 ELB 호스트명 직접 조회
```

## 변경 파일

- `pkg/utils/utils.go`: `newELBDialer`, `NewELBHTTPClient` 추가; `IsURLReachable` 수정
- `pkg/stacks/thanos/deploy_chain.go`: `initGenesisAnchorState`에서 `ethclient.DialContext` → `rpc.DialOptions + rpc.WithHTTPClient`

**커밋**: trh-sdk `ca84863`

## 예상 효과

Phase 1 + Phase 2 합산 ~12분 → 실제 NLB 프로비저닝 + 파드 기동 시간(~2-4분)으로 단축.
