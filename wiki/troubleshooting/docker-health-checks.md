---
updated: 2026-05-07
sources: []
related:
  - "[[docker-compose-lifecycle]]"
  - "[[l2-deploy-local]]"
  - "[[trh-platform]]"
tags: [troubleshooting]
---

trh-platform이 Docker Compose 컨테이너 기동 후 L2 RPC가 실제로 응답할 때까지 폴링하는 헬스 체크 전략과 타임아웃/재시도 파라미터를 다루는 페이지.

---

## 개요

trh-platform은 컨테이너 start 후 `eth_chainId` RPC 호출이 성공할 때까지 주기적으로 폴링한다. 이 폴링 로직의 타임아웃·재시도 값이 잘못 설정되면 배포가 성공했음에도 UI가 "체인 기동 실패"로 잘못 보고하거나, 반대로 실제 실패를 너무 늦게 감지한다.

> **Stub 페이지** — 상세 내용은 추후 추가 예정. 관련 흐름은 [[docker-compose-lifecycle]] 참고.

---

## 알려진 이슈

- 헬스 체크 타임아웃/재시도 전략이 tech debt으로 등록되어 있음 → [[tech-debt-and-risks]]

---

## 관련 페이지

- [[docker-compose-lifecycle]] — 전체 컨테이너 생명주기 흐름
- [[l2-deploy-local]] — 로컬 L2 배포 워크플로우
