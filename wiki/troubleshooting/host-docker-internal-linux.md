---
created: 2026-05-14
severity: high
repos: trh-platform
fixed-in: trh-platform d5929a1
---

# host.docker.internal DNS 실패 — Linux 로컬 L2 배포

## 증상

```
Waiting for L2 genesis block (attempt N/3600): Post "http://host.docker.internal:8545":
dial tcp: lookup host.docker.internal on 127.0.0.11:53: no such host
```

L2 배포 시작 후 op-geth genesis 블록을 기다리는 단계에서 3600번 내내 실패.

## 원인

`localL2RPCURL()` (`trh-sdk/pkg/stacks/thanos/local_network.go:34`) 는 `/.dockerenv` 파일 존재 여부로 Docker 컨테이너 내부인지 감지한다:

```go
if _, err := os.Stat("/.dockerenv"); err == nil {
    return "http://host.docker.internal:8545"
}
return "http://localhost:8545"
```

컨테이너 내부 → `host.docker.internal:8545` 사용. 그런데 Linux에서는 `host.docker.internal`이 자동으로 DNS에 등록되지 않는다 (macOS/Windows Docker Desktop과 달리). 명시적으로 `extra_hosts`를 설정해야 한다.

trh-platform의 루트 `docker-compose.yml` (Ubuntu 서버에서 `make up`이 사용하는 파일) 에 이 설정이 누락되어 있었다. `resources/docker-compose.yml` (Electron 앱용) 에는 이미 설정되어 있었다.

## 발생 환경

- Ubuntu 24.04 LTS (또는 기타 Linux)
- `make up`으로 서비스 시작
- API로 로컬 L2 배포 시도

## 수정 (trh-platform d5929a1)

`docker-compose.yml` backend 서비스에 `extra_hosts` 추가:

```yaml
backend:
  ...
  extra_hosts:
    - "host.docker.internal:host-gateway"  # ← 추가
  dns:
    - 8.8.8.8
    - 1.1.1.1
```

`host-gateway`는 Docker Engine 20.10+에서 지원하는 특수 값으로, 컨테이너의 `/etc/hosts`에 호스트 IP를 정적으로 기록한다. DNS 조회 없이 직접 연결되므로 안정적이다.

## 복구 방법

```bash
git pull
make down
make up
```

## 관련

- [[l2-deploy-local]] — 로컬 L2 배포 전체 흐름
- [[docker-compose-lifecycle]] — 플랫폼 Docker Compose 관리
