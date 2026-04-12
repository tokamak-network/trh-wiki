---
status: awaiting_human_verify
trigger: Bridge Info 페이지에서 데이터가 "..."으로 truncate되어 표시됨
created: 2026-04-13T00:00:00Z
updated: 2026-04-13T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED 및 FIX 적용 완료
test: BridgeInfoItem.tsx 수정됨 - truncate prop 제거, w=100% 추가, Flex overflow=auto 추가
expecting: 데이터가 완전히 표시되고 수평 스크롤 가능
next_action: verification complete

## Symptoms

expected: Bridge Info 페이지에서 컨트랙트 주소, 체인 정보, 설정값 등이 완전히 표시되어야 함
actual: 데이터가 "..."으로 잘려서 표시됨
errors: 명시적 JS 에러 없음 - UI 표시 문제
reproduction: http://localhost:3001/bridge-info 접속 → 데이터 항목들이 "..."으로 truncate됨
started: 현재 로컬 Docker 컨테이너(thanos-bridge-local:latest)에서 발생
environment: next-runtime-env 패키지로 런타임에 env 읽음

## Eliminated

## Evidence

- timestamp: 2026-04-13
  checked: BridgeInfoItem.tsx 컴포넌트
  found: Input 컴포넌트에 truncate prop이 명시되어 있음 (line 29)
  implication: Chakra UI의 truncate prop은 text-overflow: ellipsis + overflow: hidden + white-space: nowrap을 자동 적용 → 데이터가 "..."으로 잘림

## Resolution

root_cause: BridgeInfoItem.tsx의 Input 컴포넌트에 truncate prop이 있어서 Chakra UI가 자동으로 text-overflow: ellipsis를 적용함. 또한 maxWidth="380px"로 고정되어 있어서 긴 데이터가 잘림.
fix: 
  1. Input에서 truncate prop 제거
  2. Input에서 maxWidth="380px" 제거
  3. Input에 w="100%" 추가하여 컨테이너 너비 전체 사용
  4. Flex 컨테이너에 overflow="auto" 추가하여 필요시 수평 스크롤 가능하게 함
verification: 빌드 성공 (npm run build), 타입 체크 통과, 변경사항 확인됨
files_changed: [src/components/bridge-info/BridgeInfoItem.tsx]
