---
updated: 2026-04-09
sources: []
related:
  - "[[trh-platform]]"
  - "[[tokamak-thanos]]"
  - "[[thanos-bridge]]"
tags: [component, core]
---

# tokamak-rollup-hub-v2

**Tokamak Rollup Hub 공식 마케팅 및 제품 허브 웹사이트**. L2 스택, 브리지, 익스플로러, 모니터링 도구 등 생태계 전체를 소개하며, TRH Desktop 플랫폼 최신 릴리즈를 GitHub API에서 동적으로 조회해 다운로드 링크를 제공한다.

URL: https://rollup-hub.tokamak.network (Vercel 배포)

---

## 역할

| 섹션 | 내용 |
|------|------|
| Landing (`/`) | 히어로 + 3D 태양계 인터랙티브 시각화, TRH Desktop 다운로드 |
| Discover (`/discover`) | 제품 카탈로그 (Stack / Integration 카테고리 필터) |
| Product Detail (`/discover/[slug]`) | Thanos Stack, Explorer, Bridge, Monitoring, DAO Candidate 개별 페이지 |
| Platform (`/platform`) | Desktop 앱 다운로드 페이지 |
| About (`/about`) | 생태계 소개 |

---

## 기술 스택

| 항목 | 버전 |
|------|------|
| Next.js | 16.0.10 (App Router) |
| React | 19.2.3 |
| TypeScript | 5 |
| Chakra UI | 3.8.1 |
| Three.js | 0.173.0 |
| react-three/fiber | 9.0.4 |
| react-three/drei | 10.0.1 |
| next-themes | 0.4.4 |

---

## 디렉토리 구조

```
src/
├── app/                    # App Router 페이지
│   ├── page.tsx            # 랜딩
│   ├── discover/           # 제품 목록 + 상세
│   ├── platform/           # Desktop 다운로드
│   └── about/
├── components/
│   ├── solar/              # Three.js 3D 태양계 컴포넌트
│   ├── layout/             # Header, Footer
│   └── ui/                 # Chakra UI 커스텀 컴포넌트
├── containers/             # 페이지별 섹션 컨테이너
│   ├── landing-page/       # Title, Solar, Detail
│   └── discover-page/      # ProductList, Accordion
├── consts/                 # 정적 데이터
│   ├── components.ts       # 제품 정의 및 카테고리
│   ├── urls.ts             # 문서/다운로드 URL
│   └── texts.ts            # 페이지 카피
├── lib/
│   └── platform.ts         # GitHub API → 최신 릴리즈 조회
└── theme.ts                # Chakra UI 커스텀 테마
```

---

## trh-platform 연동

```typescript
// src/lib/platform.ts
// GitHub API로 최신 TRH Desktop 릴리즈 조회
fetch('https://api.github.com/repos/tokamak-network/trh-platform/releases/latest')
// → DMG (Intel/ARM), Windows EXE, Linux AppImage 다운로드 링크 추출
// 폴백 버전: 1.1.12
```

정적 콘텐츠만 있는 사이트지만, **trh-platform 릴리즈에 동적으로 연동**되는 유일한 외부 데이터 소스.

---

## 소개하는 제품들

| slug | 제품 | 분류 |
|------|------|------|
| thanos-stack | OP Stack 기반 L2 롤업 | Stack |
| thanos-explorer | Blockscout 기반 블록 익스플로러 | Integration |
| thanos-bridge | L1↔L2 자산 브리지 | Integration |
| monitoring-tool | Prometheus + Grafana | Integration |
| uptime-kuma | Uptime Kuma 서비스 모니터링 | Integration |
| dao-candidate | DAO 후보 등록 / 스테이킹 | Integration |

---

## 빌드

```bash
npm run dev     # 개발 서버 (localhost:3000)
npm run build
npm start
```

환경 변수 불필요 — 모든 URL과 콘텐츠는 `src/consts/`에 정적 하드코딩.

---

## TRH 레포와의 관계

- **[[trh-platform]]** → GitHub API로 최신 릴리즈 버전 조회 및 다운로드 링크 노출
- **[[tokamak-thanos]]** → Thanos Stack 제품 페이지에서 소개
- **[[thanos-bridge]]** → Bridge 제품 페이지에서 소개
- trh-backend, trh-sdk와 직접 코드 연동 없음
