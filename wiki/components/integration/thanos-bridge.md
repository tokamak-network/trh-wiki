---
updated: 2026-04-09
sources: []
related:
  - "[[tokamak-thanos]]"
  - "[[trh-sdk]]"
tags: [component, integration]
---

# thanos-bridge

**Thanos L2 ↔ L1 자산 브리지 DApp**. Next.js 프론트엔드로 ETH, TON, USDT, USDC, ERC-20 토큰의 L1→L2 입금(Deposit)과 L2→L1 출금(Withdrawal) UI를 제공한다.

Docker Hub: `tokamaknetwork/trh-op-bridge-app:latest`

---

## 역할

| 기능 | 설명 |
|------|------|
| Deposit | L1 → L2 자산 이동 (즉시) |
| Withdraw | L2 → L1 자산 이동 (Initiate → Prove → Finalize 3단계) |
| 토큰 지원 | ETH, native TOKAMAK, USDT, USDC, ERC-20 |
| 출금 추적 | tx hash 파일 다운로드 → 나중에 Prove/Finalize 재접속 가능 |

---

## 기술 스택

| 항목 | 버전 |
|------|------|
| Next.js | 15.5.9 (App Router) |
| React | 19.2.3 |
| TypeScript | 5.4.5 |
| @tokamak-network/thanos-sdk | 0.0.14-dev |
| Wagmi | 2.13.3 |
| Viem | 2.21.51 |
| Ethers.js | 5.7.2 |
| Chakra UI | 3.2.1 |
| Jotai | 2.10.3 |

---

## 디렉토리 구조

```
src/
├── app/                    # Next.js App Router 페이지
│   ├── bridge/             # 메인 브리지 UI
│   ├── bridge-info/        # 거래 내역 조회
│   └── account/            # 계정 페이지
├── components/
│   ├── deposit-withdraw/   # 핵심 브리지 UI (입력, 네트워크, 주소)
│   ├── wallet-connect/     # 지갑 연결
│   └── modals/             # 확인 모달
├── hooks/bridge/           # 브리지 커스텀 훅
│   ├── useThanosSDK.tsx    # CrossChainMessenger 초기화
│   ├── useDeposit.tsx      # Deposit 로직
│   └── useWithdraw.tsx     # Withdraw 로직 (Prove/Finalize 포함)
├── config/
│   ├── network.ts          # L1/L2 체인 정의
│   └── wagmi.config.ts     # Wagmi 설정
├── constants/
│   ├── contract.ts         # L2 컨트랙트 주소
│   └── token.ts            # 지원 토큰 목록
└── jotai/                  # 전역 상태 (bridge, loading, wallet)
```

---

## 핵심 훅

| 훅 | 역할 |
|----|------|
| `useThanosSDK` | `CrossChainMessenger` 초기화, Paymaster 래핑 지원 |
| `useDeposit` | `bridgeETH()`, `bridgeNativeToken()`, `approveERC20()` 호출 |
| `useWithdraw` | 출금 개시, tx hash 파일 다운로드 생성 |
| `useApprove` | 표준/USDC 브리지 토큰 승인 |
| `useTokenBalance` | 연결된 계정의 토큰 잔액 조회 |

---

## 환경 변수

```bash
# L1/L2 체인 설정
NEXT_PUBLIC_L1_CHAIN_ID=
NEXT_PUBLIC_L2_CHAIN_ID=
NEXT_PUBLIC_L1_RPC_URL=
NEXT_PUBLIC_L2_RPC_URL=

# 브리지 컨트랙트 주소
NEXT_PUBLIC_OPTIMISM_PORTAL_ADDRESS=
NEXT_PUBLIC_STANDARD_BRIDGE_ADDRESS=
NEXT_PUBLIC_L1_CROSS_DOMAIN_MESSENGER_ADDRESS=

# 타이밍
NEXT_PUBLIC_BATCH_SUBMISSION_FREQUENCY=
NEXT_PUBLIC_OUTPUT_ROOT_FREQUENCY=
NEXT_PUBLIC_CHALLENGE_PERIOD=
```

---

## 빌드

```bash
yarn install
yarn dev        # 개발 서버 (localhost:3000)
yarn build
yarn start

# Docker
docker build -t thanos-bridge:latest .
```

---

## TRH 레포와의 관계

- **[[tokamak-thanos]]** → `@tokamak-network/thanos-sdk`(v0.0.14-dev)를 직접 import — `CrossChainMessenger` 사용
- **tokamak-thanos-stack** → AWS 배포 시 `op-bridge` Helm 차트(v1.0.2)로 K8s에 배포
- trh-backend, trh-platform과는 직접 연동 없음 — 순수 프론트엔드 DApp
