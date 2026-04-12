---
status: awaiting_human_verify
trigger: "로컬 브릿지 배포 후 Withdraw를 위한 네트워크 전환 불가"
created: 2026-04-13T00:00:00Z
updated: 2026-04-13T00:00:00Z
---

## Current Focus

status: fix applied and verified through build
hypothesis_confirmed: isHTTPS() 함수가 host.docker.internal을 허용하지 않음 (현재 L2_RPC=http://host.docker.internal:8545)
fix_applied: src/utils/network.ts의 isHTTPS() 함수에 host.docker.internal 추가
verification_status: npm run build 성공, git commit fed9616 완료
next_action: 사용자 환경에서 Withdraw 기능 검증 필요

## Symptoms

expected: Withdraw 탭 클릭 또는 우상단 네트워크 전환 버튼 클릭 시 MetaMask/지갑에서 L2 네트워크(localhost:8545)로 자동 스위치 요청이 발생해야 함
actual: "You can't automatically switch the chain in this app. Please try to add the network in your wallet manually." 경고 모달 표시. 네트워크 전환 팝업이 지갑에 전혀 나타나지 않음
errors: 브라우저에서 "You can't automatically switch the chain in this app. Please try to add the network in your wallet manually. Read about it more here" 경고 모달
reproduction: localhost:3001/bridge 접속 → Withdraw 탭 클릭 또는 우상단 네트워크 전환 시도
timeline: 로컬 브릿지 배포 후 발생
environment: Bridge URL http://localhost:3001/bridge, Local L2 RPC http://localhost:8545

## Eliminated

## Evidence

- timestamp: 2026-04-13
  checked: InvalidRPCWarningModal.tsx 소스 코드
  found: "You can't automatically switch the chain in this app" 메시지는 InvalidRPCWarningModal 컴포넌트에서 제공됨
  implication: 모달을 열게 하는 조건이 있고, jotaiInvalidRPCWarningModalOpen atom을 사용하여 제어됨

- timestamp: 2026-04-13
  checked: useNetwork.ts switchChain 로직
  found: switchChainAsync 실패 시, getRPCUrlFromChainId(chainId)의 결과가 "https://"로 시작하지 않으면 InvalidRPCWarningModal을 열도록 설정
  implication: localhost:8545는 https://가 아니므로 로컬 L2 네트워크 전환 시에도 경고 모달이 표시됨

- timestamp: 2026-04-13
  checked: network.ts 유틸리티 함수
  found: isHTTPS 함수가 이미 존재하고, localhost/127.0.0.1을 명시적으로 허용하는 로직이 있음 (라인 17-25)
  implication: useNetwork.ts에서 이 함수를 사용하지 않고 단순히 startsWith("https://")로만 체크하고 있는 것이 버그

- timestamp: 2026-04-13
  checked: Withdraw 탭 클릭 흐름
  found: DepositWithdrawTab.tsx 라인 17에서 Withdraw 버튼 클릭 시 switchToL2() 호출
  implication: switchToL2() → switchChain(l2Chain.id) → switchChainAsync 실패 → 경고 모달 표시

- timestamp: 2026-04-13 (checkpoint feedback)
  checked: useNetwork.ts 확인 후 현재 L2_RPC 재조사
  found: useNetwork.ts는 이미 isHTTPS를 import하여 사용 중이나, isHTTPS 함수의 hostname 체크 (라인 21)가 localhost/127.0.0.1만 포함하고 host.docker.internal은 미포함
  implication: L2_RPC=http://host.docker.internal:8545일 경우 isHTTPS(rpcUrl)이 false 반환 → 여전히 경고 모달 표시

- timestamp: 2026-04-13
  checked: network.ts isHTTPS 함수 라인 17-25
  found: hostname === "localhost" || hostname === "127.0.0.1" (host.docker.internal 미포함)
  implication: Docker 환경에서 host.docker.internal을 사용할 때만 경고 모달이 뜸

## Resolution

root_cause: |
  Two-layer issue:
  1. useNetwork.ts는 이미 isHTTPS() 함수를 올바르게 사용 중 (파일 라인 4, 24)
  2. 하지만 isHTTPS() 함수의 hostname 체크가 불완전함
     - localhost (http://localhost:8545) → 허용됨
     - 127.0.0.1 (http://127.0.0.1:8545) → 허용됨
     - host.docker.internal (http://host.docker.internal:8545) → 미포함, 거부됨
  3. Docker 환경에서 host.docker.internal을 사용하면 여전히 경고 모달 표시

fix: |
  src/utils/network.ts의 isHTTPS() 함수 수정:
  hostname 체크에 "host.docker.internal" 추가
  
  Before:
  return hostname === "localhost" || hostname === "127.0.0.1";
  
  After:
  return (
    hostname === "localhost" ||
    hostname === "127.0.0.1" ||
    hostname === "host.docker.internal"
  );

verification: |
  1. ✅ npm run build 성공 (구문 에러, 타입 에러 없음)
  2. ✅ git diff 검토: 정확하고 최소한의 변경
  3. ✅ 커밋: fed9616 (fix(network): allow host.docker.internal for local RPC validation)
  4. ⏳ 사용자의 실제 환경(Docker + L2_RPC=http://host.docker.internal:8545)에서 Withdraw 기능 검증 필요
  
files_changed: 
  - src/utils/network.ts (isHTTPS() 함수에 host.docker.internal 추가)
