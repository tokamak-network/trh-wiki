---
updated: 2026-05-07
sources: []
related:
  - "[[deposit-tx]]"
  - "[[cross-trade]]"
  - "[[l1-deposit-tx-pitfalls]]"
tags: [troubleshooting]
---

L1 Deposit Transaction 전송 후 L2에서 실제로 실행되었는지 확인하는 폴링 전략을 다루는 페이지.

---

## 개요

`OptimismPortal.depositTransaction()`으로 L1에서 트랜잭션을 전송하면, L2에서 해당 deposit tx가 실행될 때까지 지연이 있다. trh-sdk 및 CrossTrade 배포 로직은 이 실행 여부를 확인하기 위해 L2 RPC를 폴링한다.

> **Stub 페이지** — 상세 내용은 추후 추가 예정. 관련 함정 목록은 [[l1-deposit-tx-pitfalls]] 참고.

---

## 핵심 포인트

- L1 tx receipt 확인만으로는 충분하지 않음 — L2 실행 여부를 별도로 확인해야 함
- 폴링 대상: L2에서 deposit tx에 의해 배포된 컨트랙트 주소에 코드가 있는지 (`eth_getCode`)

---

## 관련 페이지

- [[deposit-tx]] — L1→L2 Deposit Transaction 패턴 개요
- [[l1-deposit-tx-pitfalls]] — 배포 시 발생하는 13가지 함정
- [[cross-trade]] — CrossTrade DeFi 통합 모듈
