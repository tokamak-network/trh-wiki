---
title: op-bridge Thanos SDK 초기화 crash — L1UsdcBridge 미배포 시
created: 2026-05-14
type: troubleshooting
---

# op-bridge Thanos SDK 초기화 crash — L1UsdcBridge 미배포 시

## 증상

`http://localhost:3001/bridge` 접속 시 콘솔에서:

```
Error initializing Thanos SDK: TypeError: Cannot read properties of undefined (reading 'l1')
    at f.getBridgeAdapters (700-0e8011c16910d479.js:1:455920)
    at new y (700-0e8011c16910d479.js:1:232581)
    at page-85aff03da16015e2.js:1:14710
```

Deposit 버튼이 비활성 상태, bridge UI 전혀 동작하지 않음.

## 근본 원인

`@tokamak-network/thanos-sdk`의 `getBridgeAdapters()` 내부 로직:

```ts
...(CONTRACT_ADDRESSES[l2ChainId] || opts?.contracts?.l1?.L1StandardBridge
  ? {
      Usdc: {
        l1Bridge:
          opts?.contracts?.l1?.L1UsdcBridge ||           // "" → falsy
          CONTRACT_ADDRESSES[l2ChainId].l1.L1UsdcBridge, // undefined.l1 → CRASH
      },
    }
  : {}),
```

로컬 배포에서 USDC 토큰이 없으면 `L1UsdcBridgeProxy`가 배포되지 않는다.
→ `BridgeL1USDCBridgeAddress` 가 빈 문자열이 됨
→ compose 파일: `NEXT_PUBLIC_L1_USDC_BRIDGE_ADDRESS=` (empty)
→ SDK: `opts?.contracts?.l1?.L1UsdcBridge` 가 빈 문자열(falsy)
→ `CONTRACT_ADDRESSES[l2ChainId]` 는 로컬 체인 ID라 undefined
→ `undefined.l1` → TypeError crash

조건: `L1StandardBridge`는 항상 배포되므로(truthy) 분기가 true 쪽으로 진입하지만, `L1UsdcBridge`는 없어서 fallback 시 crash.

## 해결

`trh-sdk/pkg/stacks/thanos/templates/local-compose.yml.tmpl` 수정:

```yaml
# 수정 전
- NEXT_PUBLIC_L1_USDC_BRIDGE_ADDRESS={{.BridgeL1USDCBridgeAddress}}

# 수정 후
- NEXT_PUBLIC_L1_USDC_BRIDGE_ADDRESS={{if .BridgeL1USDCBridgeAddress}}{{.BridgeL1USDCBridgeAddress}}{{else}}0x0000000000000000000000000000000000000000{{end}}
```

Zero address는 non-empty(truthy)이므로 SDK가 fallback하지 않고 직접 사용한다.
USDC 브릿지가 배포되지 않은 경우 zero address를 사용하면 실제 USDC 브릿징 시도 시 revert되지만, 초기화 crash는 방지된다.

**수정 커밋**: `d0b7413` (main), `7c0915b` (feat/l2-deploy-optimization)

## 현재 배포 핫픽스

이미 생성된 compose 파일에 대한 즉시 수정:

```bash
# 1. compose 파일 패치 (trh-backend 컨테이너 내부)
docker exec trh-backend sed -i \
  's|NEXT_PUBLIC_L1_USDC_BRIDGE_ADDRESS=$|NEXT_PUBLIC_L1_USDC_BRIDGE_ADDRESS=0x0000000000000000000000000000000000000000|' \
  /app/storage/deployments/Thanos/Testnet/<DEPLOYMENT_ID>/docker-compose.local.yml

# 2. op-bridge 재생성
docker exec trh-backend docker compose \
  -f /app/storage/deployments/Thanos/Testnet/<DEPLOYMENT_ID>/docker-compose.local.yml \
  --profile bridge up -d --force-recreate op-bridge
```

## 주의

- `L1UsdcBridgeProxy`는 L1 USDC 주소(`USDCAddress`)가 설정되어 있어도, USDC Bridge 컨트랙트 배포 자체가 별도 단계임
- `NEXT_PUBLIC_L1_USDC_ADDRESS`(L1 USDC 토큰 주소)와 `NEXT_PUBLIC_L1_USDC_BRIDGE_ADDRESS`(L1UsdcBridge 프록시)는 다른 값
- SDK 버그이므로 근본 수정은 `@tokamak-network/thanos-sdk` 패키지에서 해야 함
