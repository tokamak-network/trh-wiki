---
updated: 2026-04-09
sources:
  - raw/decisions/PRD-CrossTrade-TRH-Integration-v2.1.md
related:
  - "[[cross-trade]]"
  - "[[trh-backend]]"
  - "[[docker-compose-lifecycle]]"
tags: [decision]
---

# Decision: CrossTrade dApp에 별도 Docker Compose 파일 사용

**결정:** CrossTrade dApp 컨테이너는 기존 `docker-compose.yml`에 추가하지 않고 **별도 `docker-compose.crosstrade.yml` 파일**에 정의한다.

---

## 문제

CrossTrade dApp은 DeFi/Full Preset에서만 실행된다. General/Gaming Preset에서는 이 컨테이너가 불필요하다. Docker Compose에서 조건부로 서비스를 포함하는 방법이 필요하다.

---

## 검토한 대안

### 대안 1: Docker Compose `profiles:` (v3.9+)

```yaml
# docker-compose.yml
services:
  crosstrade-dapp:
    image: tokamaknetwork/cross-trade-dapp
    profiles: ["crosstrade"]
```

DeFi/Full Preset일 때만 `docker compose --profile crosstrade up` 실행.

**거부 이유:** 현재 trh-platform의 `docker-compose.yml`은 `version: "3.8"`이다. profiles는 Compose spec v3.9+, Compose V2에서만 지원된다. 버전 업그레이드 없이 사용 불가.

### 대안 2: 환경 변수 게이팅 (env-gated entrypoint)

```yaml
crosstrade-dapp:
  entrypoint: ["/bin/sh", "-c", "if [ -z \"$ENABLE_CROSSTRADE\" ]; then exit 0; fi; ..."]
```

**거부 이유:** 서비스 정의가 항상 존재하므로 이미지가 항상 pull됨. 불필요한 이미지 다운로드 발생.

### 선택: 별도 Compose 파일

```yaml
# docker-compose.crosstrade.yml
services:
  crosstrade-dapp:
    image: tokamaknetwork/cross-trade-dapp@sha256:<digest>
    ports:
      - "3001:3000"
    environment:
      - NEXT_PUBLIC_CHAIN_CONFIG_L2_L1=${CHAIN_CONFIG_L2_L1}
      - NEXT_PUBLIC_CHAIN_CONFIG_L2_L2=${CHAIN_CONFIG_L2_L2}
      - NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=${WALLETCONNECT_PROJECT_ID}
    depends_on:
      - backend
    restart: unless-stopped
```

Backend가 DeFi/Full Preset일 때만 이 파일을 `-f` 플래그로 추가:

```bash
# General/Gaming
docker compose -f docker-compose.yml up -d

# DeFi/Full
docker compose -f docker-compose.yml -f docker-compose.crosstrade.yml up -d
```

---

## 선택 이유

| 기준 | 별도 파일 | profiles | env-gated |
|------|---------|----------|-----------|
| compose 버전 호환성 | ✅ 3.8+ | ❌ 3.9+ 필요 | ✅ |
| 이미지 pull 조건부 | ✅ 파일 미포함 시 안 당김 | ✅ profile 미활성 시 | ❌ 항상 당김 |
| Backend 코드 변경 | 최소 (`-f` 추가) | 최소 | 복잡 |
| 가독성 | ✅ 명확한 분리 | ✅ | ❌ |

---

## Backend 구현 포인트

`trh-backend/pkg/services/thanos/deployment.go`에서 Docker Compose 명령어를 구성할 때 CrossTrade 여부에 따라 `-f` 플래그를 동적으로 추가한다.

```go
composeFiles := []string{"-f", "docker-compose.yml"}
if crossTradeEnabled {
    composeFiles = append(composeFiles, "-f", "docker-compose.crosstrade.yml")
}
```
