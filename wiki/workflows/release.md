---
updated: 2026-04-15
sources:
  - raw/architecture/tech-stack.md
related:
  - "[[trh-platform]]"
  - "[[trh-backend]]"
  - "[[trh-sdk]]"
  - "[[tokamak-rollup-hub-v2]]"
tags: [workflow]
---

# Release Process

TRH Platform 생태계의 릴리즈 빌드 및 배포 프로세스.

---

## trh-platform (Electron Desktop App)

### 빌드 타겟

| OS | 포맷 | 아키텍처 |
|----|------|---------|
| macOS | DMG | x64 + arm64 (Universal Binary) |
| Windows | NSIS 인스톨러 | x64 |
| Linux | AppImage | x64 |

```bash
cd trh-platform
npm run build        # 렌더러 Vite 빌드
npm run dist         # electron-builder로 패키징 (OS별 자동 감지)
```

### GitHub Releases 연동

완성된 바이너리는 GitHub Releases에 업로드된다. `tokamak-rollup-hub-v2` 마케팅 사이트가 GitHub API로 최신 릴리즈를 조회해 다운로드 링크를 제공한다:

```js
// tokamak-rollup-hub-v2에서 사용하는 패턴
fetch('https://api.github.com/repos/tokamak-network/trh-platform/releases/latest')
// → DMG (Intel/ARM), Windows EXE, Linux AppImage 링크 추출
```

---

## trh-backend (Go)

### Docker 이미지 빌드

멀티스테이지 빌드 (Ubuntu 24.04 base):
- Node.js 20.16.0 번들 (Foundry forge/cast/anvil 포함)
- CGO disabled

```bash
docker build -t tokamaknetwork/trh-backend:<tag> .
docker push tokamaknetwork/trh-backend:<tag>
```

Docker Hub: `tokamaknetwork/trh-backend`

---

## trh-sdk (Go)

```bash
go build -o trh .
```

Docker Hub: `tokamaknetwork/trh-sdk` (linux/amd64 + arm64)

---

## 버전 관리 원칙

- trh-backend는 `go.mod`에서 `trh-sdk` 버전을 직접 고정한다 (`github.com/tokamak-network/trh-sdk v1.0.5`)
- trh-platform은 `package.json`에서 Electron 버전을 고정한다
- Docker 이미지는 sha256 digest로 고정하는 것을 권장 (`docker-compose.crosstrade.yml` 패턴 → [[separate-compose-for-crosstrade]])
