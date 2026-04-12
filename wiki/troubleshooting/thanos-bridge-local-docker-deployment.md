---
updated: 2026-04-13
sources:
  - raw/sessions/debug-network-switch-failure-on-local-bridge-withdraw.md
  - raw/sessions/debug-env-vars-not-applied-localhost-3001-bridge.md
  - raw/sessions/debug-bridge-info-data-truncated-with-ellipsis.md
  - raw/sessions/debug-withdraw-network-switch-balance-zero.md
related:
  - "[[thanos-bridge]]"
  - "[[l2-deploy-local]]"
  - "[[port-conflicts]]"
tags: [troubleshooting, docker, thanos-bridge]
---

# Thanos Bridge — 로컬 Docker 배포 트러블슈팅

로컬에서 `thanos-bridge` Docker 이미지를 빌드하고 실행할 때 발생하는 주요 문제 4가지.

---

## 1. 환경 변수가 컨테이너에 적용되지 않음

### 증상
- 브릿지 UI에 이전 설정(다른 체인명, 잘못된 RPC)이 표시됨
- `.env`를 수정하고 `docker build`를 다시 해도 변화 없음

### 원인

`thanos-bridge`는 `next-runtime-env` 패키지를 사용해 `NEXT_PUBLIC_*` 변수를 **빌드 타임이 아닌 런타임**에 읽는다.

- `src/config/network.ts`에서 `env()` 함수로 환경 변수 참조
- `src/app/layout.tsx`의 `<PublicEnvScript />`가 서버 `process.env`를 브라우저 `window.__NEXT_PUBLIC_ENV__`에 주입
- Next.js standalone 모드는 `.env` 파일을 자동으로 로드하지 않음

따라서 이미지에 `.env`를 COPY해도, `docker run` 시 `-e` 플래그로 주입하지 않으면 변수가 없는 상태로 실행된다.

### 해결

```bash
docker run -d \
  --name <container-name> \
  -p 3001:3000 \
  -e NEXT_PUBLIC_L2_CHAIN_ID=111551188141 \
  -e NEXT_PUBLIC_L2_CHAIN_NAME=ect-defi-crosstrade \
  -e NEXT_PUBLIC_L2_RPC=http://localhost:8545 \
  -e NEXT_PUBLIC_L2_NATIVE_CURRENCY_SYMBOL=ETH \
  -e NEXT_PUBLIC_L2_NATIVE_CURRENCY_NAME=Ether \
  thanos-bridge-local:latest
```

> **주의**: `Dockerfile`에 `COPY .env* ./`를 추가하면 개발용 `.env`가 이미지에 번들되어 환경 분리가 깨진다. 권장 패턴은 이미지에 `.env`를 포함하지 않고, 실행 시 `-e` 플래그로 주입하는 것이다.

---

## 2. Withdraw 탭 클릭 시 "You can't automatically switch the chain" 경고 모달

### 증상
- Withdraw 탭 클릭 또는 상단 네트워크 전환 버튼 클릭 시 경고 모달만 표시됨
- MetaMask에 네트워크 전환/추가 팝업이 전혀 뜨지 않음

### 원인

`src/hooks/network/useNetwork.ts`의 `switchChain()` catch 블록에서 RPC URL 검증 방식의 불일치:

```typescript
// 버그: http://localhost:8545 등 로컬 RPC URL도 경고 모달 트리거
if (!rpcUrl.startsWith("https://")) {
  setInvalidRPCWarningModalOpen(true);
}

// 수정: isHTTPS() 유틸이 localhost/127.0.0.1을 허용
if (!isHTTPS(rpcUrl)) {
  setInvalidRPCWarningModalOpen(true);
}
```

`src/utils/network.ts`에 이미 `isHTTPS()` 유틸이 존재하지만, 초기 구현에서 사용하지 않았다.

### 해결

`src/hooks/network/useNetwork.ts`에서 `isHTTPS` import 추가 후 사용 (커밋: 4dcc5fb).

`src/utils/network.ts`의 `isHTTPS()` 허용 목록:
- `https://` — HTTPS 프로토콜
- `localhost` — 로컬 개발
- `127.0.0.1` — 로컬 개발
- `host.docker.internal` — Docker 컨테이너 내부에서 호스트 접근 (커밋: fed9616)

---

## 3. Docker 컨테이너 내부 RPC vs 브라우저 RPC 불일치

### 증상
- `host.docker.internal:8545`를 L2 RPC로 설정했을 때 잔액이 모두 0으로 표시됨
- `isHTTPS()`에 `host.docker.internal` 추가 후에도 잔액 0이 지속됨

### 원인

`host.docker.internal`은 Docker 컨테이너 내부(서버 사이드)에서는 호스트에 접근 가능하지만, **브라우저(클라이언트 사이드)**에서는 해석되지 않는다.

`NEXT_PUBLIC_L2_RPC`는 브라우저에서 직접 사용되는 값이므로 반드시 **브라우저에서 접근 가능한 URL**이어야 한다.

| 컨텍스트 | 사용할 URL |
|---------|-----------|
| 컨테이너 내부 (SSR) | `http://host.docker.internal:8545` |
| 브라우저 (CSR, wagmi) | `http://localhost:8545` |

### 해결

`NEXT_PUBLIC_L2_RPC=http://localhost:8545`로 설정한다. wagmi가 브라우저에서 RPC를 호출하므로 `localhost`여야 한다.

---

## 4. Bridge Info 페이지에서 데이터가 "..."으로 잘려 표시됨

### 증상
- `/bridge-info` 페이지의 컨트랙트 주소, 체인 정보 등이 "..."으로 truncate됨

### 원인

`src/components/bridge-info/BridgeInfoItem.tsx`의 `<Input>` 컴포넌트에 Chakra UI `truncate` prop이 적용되어 있었음.

`truncate` prop은 `text-overflow: ellipsis + overflow: hidden + white-space: nowrap`을 자동 적용한다. 또한 `maxWidth="380px"` 고정으로 긴 주소가 잘렸다.

### 해결

```tsx
// Before
<Input truncate maxWidth={"380px"} value={content} ... />

// After
<Input w={"100%"} value={content} ... />
// + Flex 컨테이너에 overflow="auto" 추가
```

---

## 배포 시 빠른 체크리스트

```bash
# 1. 이미지 빌드
docker build -t thanos-bridge-local:latest .

# 2. 기존 컨테이너 제거
docker rm -f <old-container>

# 3. 환경 변수 명시 후 실행
docker run -d \
  --name thanos-bridge-local \
  -p 3001:3000 \
  -e NEXT_PUBLIC_L1_CHAIN_ID=<l1-chain-id> \
  -e NEXT_PUBLIC_L2_CHAIN_ID=<l2-chain-id> \
  -e NEXT_PUBLIC_L2_CHAIN_NAME=<l2-chain-name> \
  -e NEXT_PUBLIC_L2_RPC=http://localhost:<l2-rpc-port> \
  -e NEXT_PUBLIC_L2_NATIVE_CURRENCY_SYMBOL=<symbol> \
  -e NEXT_PUBLIC_L2_NATIVE_CURRENCY_NAME=<name> \
  thanos-bridge-local:latest

# 4. 환경 변수 주입 확인
docker exec thanos-bridge-local env | grep NEXT_PUBLIC_L2
```
