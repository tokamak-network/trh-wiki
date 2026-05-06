---
updated: 2026-05-06
---

# Block Explorer Update Pattern

## 결정

Block Explorer 의 사용자 설정(CoinMarketCap key/token id, WalletConnect project id)을
변경할 때 `helm install` 재실행이 아닌 별도 `Update` 경로를 통해 `helm upgrade` 를
실행한다.

## 문제 배경

`tokamak-thanos-stack` 의 blockscout-stack 차트는 backend / frontend 두 개의 Helm
release(`block-explorer-be-{ts}`, `block-explorer-fe-{ts}`) 로 timestamp suffix 가
붙어 install 된다. Install 함수는 pod 이 이미 존재하면 단순히 기존 ingress URL 을
반환하고 입력값을 무시했다 → 사용자가 나중에 CMC 키를 추가해도 반영 불가.

## 해결: Install / Update 분리

### API 라우트

| Method | Path                                              | Action                |
|--------|---------------------------------------------------|-----------------------|
| POST   | `/:id/integrations/block-explorer`                | `InstallBlockExplorer` |
| **PUT**  | `/:id/integrations/block-explorer`              | `UpdateBlockExplorer`  |
| **GET**  | `/:id/integrations/block-explorer/config`       | `GetBlockExplorerConfig` (sanitized) |
| DELETE | `/:id/integrations/block-explorer`                | `UninstallBlockExplorer` |

PUT 패턴은 monitoring 의 `UpdateEmailAlert` / `UpdateTelegramAlert` 와 동일.

GET 엔드포인트는 Update UI 프리필 용도로만 쓰이며 응답에서 DB 자격증명을 의도적으로
제외 (`SanitizeBlockExplorerConfig` → `BlockExplorerConfigResponse`). 기존
`GET /:id/integrations` 가 `Config` 전체(DB password 포함)를 노출하는 것을 우회하기
위함.

### SDK 흐름 (`trh-sdk/pkg/stacks/thanos/block_explorer.go`)

`UpdateBlockExplorer(ctx, input)`:
1. K8s nil / inputs nil / Validate 가드
2. `GetPodsByName(namespace, "block-explorer")` 가 0 이면 "not installed" 에러
3. `FilterHelmReleases(namespace, "block-explorer-be" / "block-explorer-fe")` 로 기존
   timestamp release 이름 발견 (없으면 에러)
4. `cloneSourcecode` → `.envrc` 재생성
5. `terraform init && terraform output -json rds_connection_url` (apply 없이 state
   에서 RDS URL 만 추출)
6. op-geth svc/url 재취득 → `.env` 와 `block-explorer-value.yaml` 재생성
7. `helm upgrade <be-release>` (backend 모드 values)
8. backend ingress 대기 → frontend YAML 토글 (`blockscout.enabled=false`,
   `frontend.enabled=true`, hostnames)
9. `helm upgrade <fe-release>` (frontend 모드 values)

DB credential 은 input 으로 전달되지만 실질적으로 RDS 변경에 사용되지 않는다 —
terraform output 의 `rds_connection_url` 이 state 에 저장된 install 시점 자격증명을
그대로 포함하기 때문. Validate() 통과를 위한 형식 검증 용도일 뿐.

### Backend 흐름

`BlockExplorerIntegration.Update(ctx, stackId, request)`:
1. `GetInstalledIntegration` 으로 기존 통합 record 조회
2. record 의 Config (저장된 `InstallBlockExplorerRequest`) 역직렬화 → DB 자격증명 복원
3. 백그라운드 task 로 `updateTask` 실행

`updateTask`:
- `UpdateBlockExplorerStep` deployment record 생성
- SDK `UpdateBlockExplorer` 호출 (복원한 DB 자격증명 + 신규 CMC/WC 전달)
- **helm upgrade 성공 후 bookkeeping 은 best-effort**: marshal/repo 호출 실패 시
  로그만 남기고 status 는 Completed 로 진행 (실제 chain 은 이미 갱신되었으므로
  Failed 로 되돌리면 거짓 신호)

## DTO 설계

```go
type UpdateBlockExplorerRequest struct {
    CoinmarketcapKey     string `json:"coinmarketcapKey,omitempty"`
    CoinmarketcapTokenID string `json:"coinmarketcapTokenId,omitempty"`
    WalletConnectID      string `json:"walletConnectId,omitempty"`
}
```

DB 필드 의도적 제외 — Update UI 에서 사용자가 DB 비밀번호를 입력하지 못하게 하여
실수로 RDS 와 desync 되는 것을 방지.

## InstallBlockExplorerRequest 변경

`CoinmarketcapTokenID` 필드 추가 (optional). Install/Update 양쪽이 token id 를
저장·복원하는 round-trip 을 지원하기 위함. 기존 클라이언트는 필드 없이도 동작
(omitempty + SDK 측 default fallback).

## 안 한 것

- `trh install/update block-explorer` CLI 명령 추가 — Electron 앱이 단일 진입점이고
  CLI 사용자는 별도 페르소나라서 이번 범위에서 제외.
- DB credential 변경 지원 — RDS 인스턴스 modify 가 필요하므로 별도 작업.

## 관련 파일

- `trh-sdk/pkg/stacks/thanos/block_explorer.go` — `UpdateBlockExplorer`
- `trh-backend/pkg/services/thanos/integrations/block_explorer.go` — `Update`, `updateTask`
- `trh-backend/pkg/api/handlers/thanos/integrations.go` — `UpdateBlockExplorer` handler
- `trh-backend/pkg/api/routes/route.go` — PUT route 등록
- `trh-backend/pkg/api/dtos/thanos.go` — `UpdateBlockExplorerRequest`,
  `InstallBlockExplorerRequest.CoinmarketcapTokenID`

## 알려진 제약 — 기존 설치 prefill

`InstallBlockExplorerRequest.CoinmarketcapTokenID` 가 추가된 커밋
(trh-backend `76c6819`) 이전에 설치된 block-explorer 통합 record 는 저장된
Config 에 `coinmarketcapTokenId` 필드가 없다. 이 경우 GET config endpoint
응답의 `coinmarketcapTokenId` 는 빈 문자열이 되어 Update UI 가 빈 칸으로
프리필한다. 사용자가 실제 token id 를 알고 있다면 직접 다시 입력해야 한다
(혹은 빈 칸 그대로 제출하면 exchange rates 가 비활성화됨).

신규 설치는 영향 없음.

## 검증 상태

- 단위 테스트:
  - SDK: K8s nil / inputs nil / 잘못된 input 의 early-return 만 커버
  - DTO sanitize: DB 자격증명 leak 없음을 검증
- **미검증**:
  - 실제 helm upgrade / terraform output / YAML 토글 / DB credential 보존은 라이브
    AWS 환경에서 first-run 으로 검증 예정 (테스트 환경 부재)
  - trh-platform-ui Update Settings UI 의 브라우저 동작 (dialog open/prefill/submit) —
    Electron + backend + AWS-deployed stack 조합 필요. 코드 type-check + Next.js
    build 만 통과한 상태.
