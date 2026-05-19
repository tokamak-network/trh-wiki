---
updated: 2026-05-19
sources:
  - trh-backend/pkg/api/routes/route.go
  - trh-backend/pkg/api/handlers/thanos/integrations.go
  - trh-backend/pkg/api/dtos/thanos.go
  - trh-backend/pkg/api/dtos/cross_trade.go
related:
  - "[[presets]]"
  - "[[l2-deploy-local]]"
  - "[[cross-trade]]"
  - "[[trh-backend]]"
tags: [workflow, agent-guide]
---

# Integration 별도 설치 가이드

General preset으로 배포한 L2에 integration을 사후 추가하는 방법.
모든 API는 admin JWT 인증 필요. → [[l2-deploy-local]] 참고.

---

## 공통 준비

### 1. JWT 토큰 발급

```bash
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@gmail.com","password":"admin"}' | jq -r '.token')
```

### 2. Stack ID 확인

모든 integration 경로에 `{STACK_ID}` (UUID) 필요.

```bash
curl -s http://localhost:8000/api/v1/stacks/thanos \
  -H "Authorization: Bearer $TOKEN" | jq '.data[] | {id, chainName, status}'
```

---

## Integration별 설치

### Bridge

request body 없음.

```bash
curl -s -X POST http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/bridge \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**제거**:
```bash
curl -s -X DELETE http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/bridge \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

### Block Explorer (Blockscout)

```bash
curl -s -X POST http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/block-explorer \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{
    "databaseUsername": "blockscout",
    "databasePassword": "blockscout123",
    "coinmarketcapKey": "YOUR_CMC_KEY",
    "coinmarketcapTokenId": "",
    "walletConnectId": "YOUR_WC_ID"
  }' | jq .
```

**필드 설명**:
| 필드 | 필수 | 설명 |
|------|------|------|
| `databaseUsername` | ✅ | Blockscout DB 전용 유저명 (RDS username 규칙) |
| `databasePassword` | ✅ | Blockscout DB 비밀번호 (RDS password 규칙) |
| `coinmarketcapKey` | ❌ | CoinMarketCap API Key (토큰 가격 표시용, 없으면 가격 표시 비활성) |
| `coinmarketcapTokenId` | ❌ | CMC 특정 코인 ID (없으면 심볼로 자동 검색) |
| `walletConnectId` | ❌ | WalletConnect Project ID (없으면 WC 기능 비활성) |

> CMC/WalletConnect 키가 없어도 설치 가능. 가격 표시·WC 기능만 비활성화됨.
> `coinmarketcapTokenId`를 설정하지 않으면 TON 심볼 충돌로 잘못된 가격이 표시될 수 있음. → [[blockscout-wrong-coin-price]]

**현재 설정 조회**:
```bash
curl -s http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/block-explorer/config \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**설정 업데이트** (재설치 없이 CMC/WC 키만 변경):
```bash
curl -s -X PUT http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/block-explorer \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"coinmarketcapKey":"NEW_KEY","walletConnectId":"NEW_WC_ID"}' | jq .
```

**제거**:
```bash
curl -s -X DELETE http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/block-explorer \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

### Monitoring (Grafana + AlertManager)

```bash
curl -s -X POST http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/monitoring \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{
    "grafanaPassword": "admin123",
    "loggingEnabled": false,
    "alertManager": {
      "telegram": {
        "enabled": false,
        "apiToken": "",
        "criticalReceivers": []
      },
      "email": {
        "enabled": false,
        "smtpSmarthost": "",
        "smtpFrom": "",
        "smtpAuthPassword": "",
        "alertReceivers": []
      }
    }
  }' | jq .
```

**Telegram 알림 활성화 예시**:
```json
"telegram": {
  "enabled": true,
  "apiToken": "BOT_TOKEN",
  "criticalReceivers": [{"chatId": "-100XXXXXXXXXX"}]
}
```

**제거**:
```bash
curl -s -X DELETE http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/monitoring \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

### System Pulse (Uptime Kuma)

request body 없음.

```bash
curl -s -X POST http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/system-pulse \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**제거**:
```bash
curl -s -X DELETE http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/system-pulse \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

### CrossTrade (로컬)

로컬 배포 전용 엔드포인트 (`-local` suffix). request body 없음.

```bash
curl -s -X POST http://localhost:8000/api/v1/stacks/thanos/{STACK_ID}/integrations/cross-trade-local \
  -H "Authorization: Bearer $TOKEN" | jq .
```

> AWS 배포용 CrossTrade (`POST /integrations/cross-trade`)는 `mode`, `projectID`, L1/L2 체인 config, private key 등 복잡한 파라미터가 필요하므로 별도 작업 필요. → [[cross-trade]]

---

## Preset별 포함 Integration

| Integration | General | DeFi | Gaming | Full |
|---|:---:|:---:|:---:|:---:|
| Bridge | ✅ | ✅ | ✅ | ✅ |
| Block Explorer | ✅ | ✅ | ✅ | ✅ |
| Monitoring | - | ✅ | ✅ | ✅ |
| System Pulse | - | ✅ | ✅ | ✅ |
| CrossTrade | - | ✅ | - | ✅ |
| DRB VRF | - | - | ✅ | ✅ |
| AA Paymaster | - | - | ✅ | ✅ |

General preset 배포 후 위 표의 미포함 항목을 필요에 따라 개별 추가할 수 있다.

---

## 서비스 포트 (로컬)

| 서비스 | URL |
|--------|-----|
| L2 RPC | http://localhost:8545 |
| Bridge | http://localhost:3001 |
| Block Explorer | http://localhost:4001 |
| Grafana | http://localhost:3002 |
| Uptime Kuma | http://localhost:3003 |
