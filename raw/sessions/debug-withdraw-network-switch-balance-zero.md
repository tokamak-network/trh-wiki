---
status: resolved
trigger: "Investigate and fix multiple issues on local bridge at http://localhost:3001/bridge: 1) withdraw 시 네트워크 전환 여전히 안됨, 2) 잔액 0 표시, 3) native token이 TON이 아닌 ETH여야 함"
created: 2026-04-13T00:00:00Z
updated: 2026-04-13T12:00:00Z
symptoms_prefilled: true
---

## Current Focus

status: VERIFICATION PHASE
hypothesis: Environment variables were not being passed to docker container; .env fallback values were used instead
test_results: Fixed by (1) removing .env* from Dockerfile, (2) explicitly passing RPC URLs in wagmi.config.ts, (3) starting container with explicit -e env vars
container_env_vars: VERIFIED ✓ - docker exec shows correct values
next_action: AWAITING USER VERIFICATION - test bridge at http://localhost:3001/bridge

## Symptoms

expected:
- Withdraw 탭 클릭 시 MetaMask에 L2(ect-defi-crosstrade) 네트워크 전환/추가 팝업이 뜨거나 체인이 자동 전환되어야 함
- 지갑 잔액(ETH, 토큰)이 실제 값으로 표시되어야 함
- L2 native token이 ETH로 표시되어야 함

actual:
- 네트워크 전환 시 "You can't automatically switch the chain" 경고 모달이 여전히 뜸
- 모든 잔액이 0으로 표시됨
- L2 native token이 TON으로 표시됨 (잘못된 값)

errors: 명시적 JS 에러 없음 (브라우저 콘솔 확인 필요)

reproduction:
- http://localhost:3001/bridge 접속
- Withdraw 탭 클릭 → 네트워크 전환 시도 → 경고 모달
- 잔액 필드가 모두 0.0

started: 로컬 브릿지 Docker 컨테이너 실행 중

## Eliminated

## Evidence

- timestamp: 2026-04-13
  checked: wagmi version and next.config.js
  found: wagmi 2.19.5 with standalone output enabled
  implication: next-runtime-env should work at container startup

- timestamp: 2026-04-13
  checked: src/config/wagmi.config.ts transport setup
  found: |
    transports: {
      [l1Chain.id]: http(),
      [l2Chain.id]: http(),
    }
    In wagmi 2.x, http() without arguments SHOULD use the chain's rpcUrls
  implication: Transports should inherit RPC URLs from chain objects

- timestamp: 2026-04-13
  checked: src/config/network.ts environment reading
  found: |
    Uses next-runtime-env's env() function to read NEXT_PUBLIC_L2_RPC at runtime
    Chain object definition is dynamic based on env vars
    PublicEnvScript is in layout.tsx head
  implication: Environment variables are being read, but timing might matter

- timestamp: 2026-04-13
  checked: .env file dev values
  found: |
    NEXT_PUBLIC_L2_CHAIN_ID=111551119090 (should be 111551188141 for local)
    NEXT_PUBLIC_L2_NATIVE_CURRENCY_SYMBOL=TOKAMAK (should be ETH)
    NEXT_PUBLIC_L2_RPC=https://rpc.thanos-sepolia.tokamak.network (should be http://host.docker.internal:8545)
  implication: Docker container is using dev .env values because docker run -e isn't overriding properly

- timestamp: 2026-04-13
  checked: Dockerfile COPY strategy
  found: COPY --chown=node:node .env* ./
  implication: .env file is copied into container, which means docker run -e flags MUST override it at runtime

## Resolution

root_cause: |
  **ROOT CAUSE IDENTIFIED**: 
  
  The issue is that wagmi.config and network.ts use next-runtime-env's env() function, which on the server-side reads from process.env, and on the client-side reads from window.__NEXT_PUBLIC_ENV__. However:
  
  1. The .env file in the project has DEV values (chain ID 111551119090, TON symbol, dev RPC)
  2. Standalone mode doesn't auto-load .env files - environment variables must be passed via docker run -e
  3. The Dockerfile copies .env but doesn't set up environment variable loading for standalone mode
  4. When docker run doesn't override NEXT_PUBLIC_L2_* variables, they fall back to .env values via next-runtime-env's defaults
  
  **Specific failures**:
  1. **Network Switch Fails**: Wagmi has chain ID 111551119090 registered, but MetaMask is asked to switch to 111551188141 (from some other source). switchChainAsync fails because the chain doesn't exist in wagmi config.
  2. **Balance Shows Zero**: If using wrong chain ID or wrong RPC, balance queries fail.
  3. **Native Currency is TON**: NEXT_PUBLIC_L2_NATIVE_CURRENCY_SYMBOL not overridden, defaults to TOKAMAK from .env

fix: |
  1. **src/config/wagmi.config.ts**: Explicitly pass RPC URLs to http() transports with env() calls
     - This ensures the RPC URLs are read from environment variables at runtime
     - Fallback to chain's default RPC if env var is not set
  
  2. **Dockerfile**: Removed COPY .env* to prevent dev .env from being bundled in production
     - Standalone mode doesn't auto-load .env files
     - Environment variables must be passed via docker run -e flags
     - This prevents accidentally using dev values when env vars aren't explicitly set
  
verification: |
  ✓ Docker image rebuilt with Dockerfile changes (removed .env* COPY)
  ✓ New container started with proper NEXT_PUBLIC_L2_* env vars:
    - NEXT_PUBLIC_L2_CHAIN_ID=111551188141
    - NEXT_PUBLIC_L2_RPC=http://localhost:8545
    - NEXT_PUBLIC_L2_NATIVE_CURRENCY_SYMBOL=ETH
    - NEXT_PUBLIC_L2_NATIVE_CURRENCY_NAME=Ether
  ✓ Container is running and accessible at http://localhost:3001
  
  ✓ USER VERIFIED (2026-04-13):
  1. Withdraw tab network switch - WORKS (correctly switches to 111551188141)
  2. Balance display - WORKS (shows actual values, not 0)
  3. Native token symbol - WORKS (shows ETH, not TON)

files_changed:
  - src/config/wagmi.config.ts (added explicit RPC URL passing to http())
  - Dockerfile (removed .env* COPY to force runtime env var passing)
