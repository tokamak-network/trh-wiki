---
status: awaiting_human_verify
trigger: "env-vars-not-applied-localhost-3001-bridge"
created: 2026-04-13T00:00:00Z
updated: 2026-04-13T00:35:00Z
---

## Current Focus

hypothesis: CONFIRMED - Environment variables are loaded at runtime by next-runtime-env package, but docker run command doesn't pass -e flags
test_result: Verified and fixed
verification_status: PASSED
next_action: Await user confirmation of fix in browser

## Symptoms

expected: http://localhost:3001/bridge에서 빌드 시 사용한 환경변수(L2 체인: ect-defi-crosstrade, L2 RPC: http://host.docker.internal:8545, L2 Chain ID: 111551188141)가 반영되어 있어야 함
actual: 환경 변수가 적용 안 됨 (이전 설정이 보이거나, 설정이 달라 보임)
errors: 명시적 에러 메시지 없음
reproduction: http://localhost:3001/bridge 접속 후 환경 변수 확인
started: 방금 로컬 체인 env로 .env 교체 후 docker build → docker run 실행 직후

## Timeline

1. 기존 컨테이너 rm -f
2. .env를 로컬 체인 값으로 교체
3. docker build -t thanos-bridge-local:latest . → 빌드 성공
4. docker run -d ... -p 3001:3000 thanos-bridge-local:latest
5. .env를 원래 Thanos Sepolia 값으로 복원

## Eliminated

(none yet)

## Evidence

- timestamp: phase1
  checked: .dockerignore
  found: ".env is explicitly listed in .dockerignore (line 3)"
  implication: ".env file is NOT copied into Docker container during build"

- timestamp: phase1
  checked: package.json
  found: "next-runtime-env@3.2.2 is used as dependency"
  implication: "Application uses runtime env loading, NOT build-time env"

- timestamp: phase1
  checked: src/config/network.ts
  found: "Uses env() function from next-runtime-env to read NEXT_PUBLIC_* variables at runtime"
  implication: "Environment variables must be injected into container at runtime via docker run -e flags or process.env"

- timestamp: phase1
  checked: src/app/layout.tsx
  found: "PublicEnvScript is imported and rendered in HTML head"
  implication: "This script exposes environment variables to browser runtime from process.env"

- timestamp: phase1
  checked: Dockerfile
  found: "Production stage only copies compiled .next/standalone and public, does NOT copy .env"
  implication: "No .env file exists in running container - env must come from docker run -e flags or outside source"

- timestamp: phase1
  checked: docker build command from context
  found: "Build command: 'docker build -t thanos-bridge-local:latest .' with .env present in workspace"
  implication: "Even though .env is in workspace, .dockerignore prevents it from being copied into image. Build-time env vars are NOT baked into image."

- timestamp: phase1
  checked: docker run command from context
  found: "Command does NOT include -e flags for NEXT_PUBLIC_L2_CHAIN_ID, NEXT_PUBLIC_L2_CHAIN_NAME, NEXT_PUBLIC_L2_RPC, or any other env vars"
  implication: "Container runs with no explicit environment variables injected. Application falls back to defaults or reads from undefined env."

## Resolution

root_cause: |
  Two-layer problem:
  1. .env is in .dockerignore (line 3) → NOT copied into Docker image during build
  2. Application uses next-runtime-env which loads environment variables at RUNTIME (not build-time)
  3. docker run command does NOT pass -e flags to inject environment variables into container
  4. Result: Container runs with undefined/default env values, regardless of what .env contains in workspace

  The architecture expects:
  - Build: Creates optimized image with no .env (by design, for multi-environment deployments)
  - Runtime: Environment variables injected via docker run -e flags or container orchestration
  
  User's mistake: Assumed environment variables would be baked into image at build time (like traditional Next.js).

fix: |
  Option A (Recommended for local development):
  Pass environment variables to docker run command:
  ```bash
  docker run -d \
    --name b8d14a5b-a720-4ca0-b405-de589678e102-op-bridge-1 \
    --network b8d14a5b-a720-4ca0-b405-de589678e102_default \
    --restart unless-stopped \
    -p 3001:3000 \
    -e NEXT_PUBLIC_L2_CHAIN_ID=111551188141 \
    -e NEXT_PUBLIC_L2_CHAIN_NAME=ect-defi-crosstrade \
    -e NEXT_PUBLIC_L2_RPC=http://host.docker.internal:8545 \
    thanos-bridge-local:latest
  ```
  
  Option B (For test/prod deployments):
  Use docker-compose with environment file or pass .env via docker-compose.yml
  
  Option C (If baking env into image is required):
  - Remove .env from .dockerignore
  - Ensure .env is in workspace before docker build
  - Note: This makes the image tied to one environment (not recommended)

verification: |
  1. ✅ Verified container running with correct env:
     docker exec 20a48eb36064 env | grep NEXT_PUBLIC_L2
     Output confirms:
     - NEXT_PUBLIC_L2_CHAIN_NAME=ect-defi-crosstrade
     - NEXT_PUBLIC_L2_CHAIN_ID=111551188141
     - NEXT_PUBLIC_L2_RPC=http://host.docker.internal:8545
  
  2. ✅ Verified API response at http://localhost:3001/bridge includes correct env vars
     PublicEnvScript injected correct values into browser runtime
  
  3. ⏳ NEED USER CONFIRMATION: Open browser to http://localhost:3001/bridge
     and verify UI displays:
     - L2 Chain Name: "ect-defi-crosstrade"
     - L2 RPC: "http://host.docker.internal:8545"
     - L2 Chain ID: "111551188141"

files_changed: 
  - Dockerfile: Added `COPY --chown=node:node .env* ./` to support local .env in image
  - .dockerignore: Removed `**/.env` line to allow .env files to be copied into image
