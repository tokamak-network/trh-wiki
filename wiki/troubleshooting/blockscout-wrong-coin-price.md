---
updated: 2026-05-14
---

# Blockscout Wrong Coin Price (Symbol Collision on CoinGecko)

## 증상

로컬 L2 배포 후 Blockscout(`localhost:4001`)에서 기대하지 않은 코인 가격이 표시됨.

예: TON fee token을 사용하는 체인에서 TON이 $0.55(Tokamak Network)가 아닌 $25.31(AT&T Ondo Tokenized Stock)로 표시됨.

추가로 `coin_price_change_percentage`가 1000% 이상의 비정상 값을 가짐.

## 원인

`COIN=TON`만 설정되고 `EXCHANGE_RATES_COINGECKO_COIN_ID`가 없으면, Blockscout이
CoinGecko에서 심볼 "TON"으로 검색한다. CoinGecko에는 "TON" 심볼을 공유하는 코인이
5개 이상 존재하며, stats fetcher와 market_history fetcher가 서로 다른 코인을 선택하여
cross-contamination이 발생한다.

| Fetcher | 선택된 코인 | 가격 |
|---------|-----------|------|
| `/api/v2/stats` | AT&T Ondo Tokenized Stock (`atnt-ondo-tokenized-stock`) | $25.31 |
| `market_history` DB | Toncoin (`the-open-network`) | $2.12 |
| 목표 | Tokamak Network (`tokamak-network`) | $0.55 |

## 해결

`EXCHANGE_RATES_COINGECKO_COIN_ID` 환경변수를 명시적으로 설정하여 심볼 모호성 제거.

trh-sdk `5a74242`에서 수정:
- `FeeTokenConfig`에 `CoinGeckoID` 필드 추가
  - TON → `tokamak-network`
  - ETH → `ethereum`
  - USDT → `tether` (단, DISABLE_EXCHANGE_RATES=true라 실제로 사용 안 됨)
  - USDC → `usd-coin` (동상)
- `local-compose.yml.tmpl`에서 non-stablecoin일 때 env var 방출:
  ```yaml
  {{- if .BlockExplorerStableCoin}}
        - DISABLE_EXCHANGE_RATES=true
  {{- else}}
        - EXCHANGE_RATES_COINGECKO_COIN_ID={{.BlockExplorerCoinGeckoID}}
  {{- end}}
  ```

## 기존 배포 수동 적용

이미 배포된 컨테이너는 재생성 필요. docker-compose.local.yml에 수동으로 환경변수 추가 후
해당 컨테이너만 재시작:

```bash
# docker-compose.local.yml의 blockscout 서비스 environment 섹션에 추가:
# - EXCHANGE_RATES_COINGECKO_COIN_ID=tokamak-network

docker compose -f /path/to/docker-compose.local.yml up -d --force-recreate blockscout
```

## 관련 Blockscout 환경변수

| 변수 | 역할 |
|------|------|
| `COIN` | 심볼 (표시용) |
| `EXCHANGE_RATES_COINGECKO_COIN_ID` | CoinGecko coin ID (명시적 조회용) |
| `DISABLE_EXCHANGE_RATES` | true이면 가격 조회 완전 비활성화 (stablecoin용) |

출처: `/app/releases/6.10.1/runtime.exs` in blockscout container.
