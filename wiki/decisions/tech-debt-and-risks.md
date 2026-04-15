---
updated: 2026-04-09
source: raw/decisions/tech-debt-and-risks.md
---

# Tech Debt and Risks

trh-platform의 알려진 버그, 기술 부채, 보안 우려, 의존성 위험 목록. 제품 안정성 개선 로드맵 참고용.

**관련:** [[trh-platform]], [[docker-health-checks]]

---

## Tech Debt

### 하드코딩된 localhost URL
- **위치:** `src/main/webview.ts:17-18`, `src/main/index.ts:70`
- **문제:** 원격 백엔드 연결 불가, 로컬 Docker 전용
- **수정 방향:** `BACKEND_API_URL`, `PLATFORM_UI_URL` 환경변수 지원 추가

### WebContentsView sandbox: false
- **위치:** `src/main/webview.ts:98`
- **상태:** 의도적 트레이드오프 (credential injection을 위해 필요)
- **수정 방향:** 미래 Electron 버전이 sandboxed context bridge 지원 시 검토

### Network guard 파싱 실패 시 허용
- **위치:** `src/main/network-guard.ts:87-89`
- **문제:** 잘못된 URL이 보안 체크를 우회
- **수정 방향:** 파싱 실패 시 차단으로 변경, 에러 케이스 로깅

### 모듈 스코프 credential 캐시
- **위치:** `src/main/aws-auth.ts:50`, `src/main/webview.ts:25`
- **문제:** 장시간 실행 시 민감 데이터 메모리 노출 위험
- **수정 방향:** 만료 타이머 추가 (AWS 60분, admin 30분), 로그아웃 시 명시적 clear

---

## Known Bugs

### ~~로컬 L2 재배포 불가 (DB↔Docker 상태 불일치)~~ — **Fixed 2026-04-15**
- **증상:** 컨테이너를 앱 외부에서 수동 제거(docker rm)하거나 백엔드 컨테이너 재시작 후 새 로컬 L2 배포 시도 시 409 Conflict 반환
- **근본 원인 1:** `trh-backend/pkg/services/thanos/stack_lifecycle.go` `checkNoActiveLocalStack()`이 DB 상태만 보고 실제 Docker 컨테이너 존재 여부를 확인하지 않음 → DB=Deployed, 컨테이너=없음 상태에서 영구 블록
- **근본 원인 2:** `trh-sdk/pkg/stacks/thanos/local_network.go` `destroyLocalNetwork()`가 compose 파일 없으면 nil 반환 → 볼륨(trh-local-config, trh-local-monitoring, `<uuid>_op-geth-data`) 정리 안 됨
- **수정:** A) `checkNoActiveLocalStack()`에 `docker ps --filter label=com.docker.compose.project=<uuid>` 조회 추가, 컨테이너 없으면 DB 자동 Terminated 보정; C) compose 파일 없을 때 `docker volume rm -f` 직접 실행

### Docker 컨테이너 수 하드코딩 (`>= 3`)
- **위치:** `src/main/docker.ts:334`
- **증상:** General/Gaming preset (CrossTrade dApp 없음) 배포 시 헬스체크가 "unhealthy" 잘못 보고
- **수정 방향:** docker-compose.yml에서 활성 서비스 수를 동적으로 읽기

### Mnemonic 버퍼 cleanup 불완전
- **위치:** `src/main/keystore.ts:120`
- **문제:** mnemonic 버퍼는 제로-필하지만 파생된 private key 문자열은 힙에 잔존
- **수정 방향:** env 객체 사용 후 래퍼로 clear, 또는 Buffer 기반 키 저장

### Docker 에러에 `(err as any)` 타입 캐스트
- **위치:** `src/main/docker.ts:600-602`
- **수정 방향:** `DockerError extends Error { errorType: string; output?: string }` 커스텀 에러 클래스

### 하드코딩된 컨테이너 이름으로 force-remove
- **위치:** `src/main/docker.ts:683-684`
- **문제:** 사용자 커스텀 docker-compose 설정 시 cleanup 실패
- **수정 방향:** docker-compose.yml에서 실제 서비스명 파싱

---

## Missing Error Handling

| 위치 | 문제 | 수정 방향 |
|------|------|---------|
| `src/main/webview.ts:128-150` | 백엔드 불통 시 빈 화면 | 연결 체크 + in-app toast |
| `src/main/index.ts:642-648` | IPC 입력 페이로드 미검증 | Zod 스키마 검증 추가 |
| `src/main/docker.ts:10, 400-402` | Docker pull timeout 600s 하드코딩 | 환경변수로 설정 가능하게 |
| `src/main/index.ts:569-590` | 백엔드 다운 시 100s 대기 후 에러 | 지수 백오프 + "still waiting" UI |

---

## Security Concerns

### Network guard 와일드카드 패턴
- **위치:** `src/main/network-guard.ts:15-27`
- `*.docker.io` 패턴이 임의 서브도메인 허용
- **권장:** `index.docker.io`, `auth.docker.io` 등 구체적 허용 목록

### Admin credential IPC 전송 (미암호화)
- **위치:** `src/main/index.ts:492-502`
- Electron DevTools에서 크레덴셜 노출 가능
- **위험도:** 낮음 (로컬 전용 앱), 개발/테스트 환경에서는 허용 가능

### Mnemonic brute-force via IPC
- **위치:** `src/main/index.ts:646`
- `keystore:preview-addresses`에 rate limit 없음
- **권장:** 초당 1 요청 제한 또는 ethers.js로 renderer 측 계산

---

## Performance Bottlenecks

| 문제 | 위치 | 개선 방향 |
|------|------|---------|
| Docker pull UI 블로킹 (최대 10분) | `docker.ts:383-449` | `--verbose` 플래그로 레이어별 실시간 진행률 |
| 3초마다 헬스체크 폴링 | `docker.ts:9, 696-722` | Docker event stream으로 전환 |
| 프로젝트 무관 컨테이너 force-remove | `docker.ts:683-691` | `--project` 플래그로 스코프 제한 |
| showPlatformView 블로킹 토큰 fetch | `webview.ts:63-78` | 뷰 먼저 생성, 백그라운드 토큰 fetch |

---

## Fragile Areas

### Docker Compose 경로 해결
- **위치:** `src/main/docker.ts:72-81`
- packaged/dev 모드에서 경로 로직이 다름
- **주의:** 디렉토리 구조 변경 시 반드시 양쪽 모드 테스트

### Tray 메뉴 update 상태 동기화
- **위치:** `src/main/index.ts:196-210, 377-419`
- `updateAvailable` 플래그가 여러 곳에 사용되어 상태 드리프트 가능

### 포트 충돌 감지 (lsof/netstat)
- **위치:** `src/main/docker.ts:95-114`
- Windows에서 `lsof` 없음 → 폴백 로직이 모든 케이스를 커버 않을 수 있음

---

## Dependencies at Risk

| 의존성 | 버전 | 위험 | 우선순위 |
|--------|------|------|---------|
| @aws-sdk | 3.1013.0 (2024 초) | 보안 취약점, 신규 기능 누락 | Medium |
| ethers | 6.13.4 | v7 마이그레이션 시 breaking changes | Low (v6 안정) |
| Electron | 33 | 4개월마다 major 버전 업 | Low (현재 안정) |

---

## Test Coverage Gaps (우선순위 순)

| 영역 | 우선순위 | 설명 |
|------|---------|------|
| Electron main process (docker.ts, aws-auth.ts, keystore.ts) | **High** | 에러 복구, 타임아웃, 동시 작업 안전성 미테스트 |
| IPC 페이로드 검증 | **High** | 잘못된 입력 시 main process 크래시 위험 |
| WebContentsView lifecycle | Medium | 메모리 누수, bounds 오계산 |
| Network guard URL 패턴 | Medium | IDN, 포트 포함 URL, 쿼리스트링 엣지 케이스 |
| PresetModule 음성 케이스 | Low | null, 빈 배열, 알 수 없는 프로퍼티 |
| Docker cleanup (커스텀 컨테이너명) | Medium | 다중 프로젝트 환경 정리 오작동 |
| CrossTrade dApp E2E (Electron) | **High** | Phase 05에서 구현 중 |

---

## Incomplete Features

| 기능 | 상태 | 설명 |
|------|------|------|
| Admin credential 영속성 | 미구현 | 앱 재시작 시 재입력 필요; keystore에 암호화 저장 필요 |
| AWS profile 세션 영속성 | 미구현 | 재시작 시 재로그인 필요 |
| CrossTrade dApp 헬스체크 IPC | 대기 중 | `docker:check-crosstrade-health` 핸들러 미구현 |
| 구조화된 에러 코드 | 미구현 | 포트 충돌 vs 네트워크 에러 vs 디스크 공간 구분 불가 |

---

*Source: `.planning/codebase/CONCERNS.md` (2026-04-09)*
