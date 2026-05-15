---
updated: 2026-05-15
source: EFP E2E test run — EFP-04 failure investigation
---

# docker exec: container name vs image name

`docker exec`는 **이미지 이름**이 아닌 **컨테이너 이름**을 요구한다.

**관련:** [[testing]], [[docker-compose-lifecycle]]

---

## 증상

```
Error response from daemon: No such container: trh-backend
```

`docker exec trh-backend cat <path>` 실행 시 컨테이너를 찾지 못함.

---

## 원인

Docker에는 **이름이 다른 두 개념**이 존재한다:

| 개념 | 예시 | 용도 |
|------|------|------|
| 이미지 이름 | `tokamaknetwork/trh-backend:latest` | `docker pull`, `docker run` |
| 컨테이너 이름 | `trh-platform-backend-1` | `docker exec`, `docker stop`, `docker logs` |

Docker Compose는 컨테이너 이름을 다음 규칙으로 자동 생성한다:

```
{project_name}-{service_name}-{replica_number}
```

예시:
- 프로젝트: `trh-platform` (디렉토리 이름 또는 `-p` 옵션)
- 서비스: `backend` (`docker-compose.yml` 서비스 키)
- 레플리카: `1` (기본값)
- 결과: `trh-platform-backend-1`

---

## 발견 경위

`stack-resolver.ts`의 `resolveContractAddresses()`가 `docker exec`로 백엔드 컨테이너 내부에서 배포 JSON을 읽을 때 기본값으로 `'trh-backend'`를 사용했다. 이 값은 이미지 이름도 컨테이너 이름도 아니므로 항상 실패했다.

EFP-04 테스트(2026-05-15)에서 `No such container: trh-backend` 에러로 발견.

---

## 수정

`tests/e2e/helpers/stack-resolver.ts:129`:

```typescript
// Before (broken):
const containerName = process.env.BACKEND_CONTAINER_NAME ?? 'trh-backend';

// After (fixed):
const containerName = process.env.BACKEND_CONTAINER_NAME ?? 'trh-platform-backend-1';
```

커밋: `trh-platform 23d11e5`

---

## 컨테이너 이름 확인 방법

```bash
# 실행 중인 컨테이너 이름 목록
docker ps --format '{{.Names}}'

# 특정 이미지를 사용하는 컨테이너 이름 확인
docker ps --format '{{.Names}}\t{{.Image}}' | grep trh-backend
```

---

## 환경변수 오버라이드

기본값과 다른 컨테이너 이름을 사용하는 경우 (e.g., 프로젝트명 커스텀 또는 `docker run --name`):

```bash
BACKEND_CONTAINER_NAME=my-backend-container npx playwright test ...
```
