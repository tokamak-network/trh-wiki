---

updated: 2026-05-19
sources: []
related:
  - "[[sequential-l2-deploy]]"
  - "[[l2-deploy-local]]"
  - "[[port-conflicts]]"
tags: [troubleshooting]
---
# Preset Deploy 409 — "a local stack is already active"

## 증상

Electron 앱 Preset Wizard **Step 3 → Deploy Rollup** 클릭 시:
- 토스트: `"Failed to initiate deployment"` (또는 수정 후: `"a local stack is already active (stackId: ..., status: ...): stop it before starting a new local deployment"`)
- 백엔드 로그: `POST /api/v1/stacks/thanos/preset-deploy → 409 Conflict`

## 원인

`trh-backend/pkg/services/thanos/stack_lifecycle.go:22-56` 의 `checkNoActiveLocalStack()` 가드:

`infraProvider = "local"` 요청이 오면, DB에 이미 **active 상태인 local stack**이 존재하는지 검사한다.

Active로 간주하는 상태:
- `Pending`
- `Deploying`
- `Deployed`
- `Updating`

조건: 해당 stack의 `Config.infraProvider == "local"`

이 조건에 걸리면 즉시 409를 반환하고 새 배포를 차단한다.
고정 포트(8545/8546/8551/9545/7300/8548/8560)를 공유하기 때문에
동시 로컬 배포가 물리적으로 불가능하기 때문이다 → [[sequential-l2-deploy]]

## 흔한 발생 경위

1. 이전 배포 시도가 Crash/강제종료되어 `Terminated`로 전환되지 않고 `Pending`/`Deploying` 상태로 남음
2. 성공적으로 배포된 local stack이 `Deployed` 상태인 채로 Dashboard에 존재
3. Wizard를 중간에 닫았다가 다시 열어 재시도하는 경우

## 해결 절차

### 1. 잔존 stack 확인

```bash
curl -s http://localhost:8000/api/v1/stacks/thanos | python3 -m json.tool
```

`"infraProvider": "local"` + status ∈ {Pending, Deploying, Deployed, Updating} 인 항목 찾기.

### 2. Dashboard에서 Terminate (권장)

Dashboard → Stacks 목록 → 해당 local stack → **Delete/Terminate** 버튼
→ 내부적으로 `docker compose down -v` 자동 수행

### 3. Docker 컨테이너/볼륨 수동 정리 (Terminate 후에도 남아있는 경우)

```bash
# 컨테이너 중지 및 삭제
docker rm -f op-geth op-node op-batcher op-proposer
docker rm -f $(docker ps -aq --filter "name=blockscout") 2>/dev/null

# 볼륨 삭제
docker volume rm op-geth-data blockscout-db-data 2>/dev/null
```

### 4. 재배포 전 검증

```bash
curl -s http://localhost:8000/api/v1/stacks/thanos | python3 -m json.tool
# → active local stack 없는 것 확인
```

확인 후 Preset Wizard Step 3에서 Deploy Rollup 재시도.

## UX 버그 (2026-04-15 수정)

`trh-platform-ui/src/lib/api.ts`의 `handleApiError()`가 axios 에러를
plain object로 변환하는데, `usePresetWizard.ts`에서 `error instanceof Error`로
분기해 백엔드 메시지를 놓치고 generic fallback을 표시했었다.

수정 후: catch 블록이 plain object의 `.message`도 읽도록 변경됨.
수정 파일: `trh-platform-ui/src/features/rollup/hooks/usePresetWizard.ts:117-123`

## 관련 문서

- [[l2-deploy-local]] — 로컬 L2 배포 전체 절차
- [[sequential-l2-deploy]] — 동시 배포 불가 원칙
- [[port-conflicts]] — 포트 충돌 해결
