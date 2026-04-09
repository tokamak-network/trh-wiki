---
updated: 2026-04-09
sources:
  - raw/architecture/local-l2-deployment-test-guide.md
related:
  - "[[l2-deploy-local]]"
  - "[[port-conflicts]]"
  - "[[trh-backend]]"
tags: [decision]
---

# Sequential L2 Deploy

L2 배포는 반드시 순차 실행해야 한다. 동시 배포는 포트 충돌을 유발한다.

**Why:** 로컬 Docker Compose L2 배포는 고정 포트(8545, 8546, 8548, 8551, 8560, 9545)를 사용한다. 두 개의 배포가 동시에 진행되면 두 번째 배포가 이미 점유된 포트에 컨테이너를 띄우려다 실패한다. 포트를 동적으로 할당하는 방식은 trh-sdk의 Docker Compose 템플릿 구조를 크게 변경해야 하므로 채택하지 않았다.

**How to apply:** trh-backend의 배포 태스크 큐는 로컬 배포 요청을 직렬화해야 한다. 동시 배포 요청이 들어오면 큐에서 대기시킨다.
