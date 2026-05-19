---
updated: 2026-05-04
sources: []
related: []
tags: [workflow]
---


# DRB Node Deployment (trh-sdk)

DRB(Distributed Random Beacon) 노드를 K8s(EKS)에 Helm으로 배포하는 설계 결정.

---

## 아키텍처

leader 1 + regular 3, 총 4개 노드를 단일 Helm release로 배포.

```
drb-vrf (Helm release)
├── leader-deployment     # NODE_TYPE=leader, port 9600
├── leader-postgres       # leader 전용 Postgres DB
├── regular-deployment-1  # NODE_TYPE=regular, port 9601
├── regular-postgres-1
├── regular-deployment-2  # NODE_TYPE=regular, port 9602
├── regular-postgres-2
├── regular-deployment-3  # NODE_TYPE=regular, port 9603
└── regular-postgres-3
```

**업그레이드**: `helm upgrade --set image.tag=<new-tag>` 한 줄로 4개 노드 동시 롤링 업데이트.

---

## CLI 진입점

```bash
trh-sdk install drb-vrf    # EKS에 leader + 3 regular Helm 배포
trh-sdk uninstall drb-vrf  # Helm release 제거
```

**주의**: `PluginDRB` 상수값은 `"drb-vrf"` (`pkg/constants/plugins.go`).

---

## 핵심 설계 결정

### 1. 단일 Helm 경로

기존에는 배포 경로가 두 갈래였다:
- leader: EKS + Terraform (`drb_leader.go`, ~1,500 lines)
- regular: EC2 직접 배포 (`drb_regular.go`, ~710 lines)

EC2 regular 노드는 이미지 업데이트 시 노드마다 SSH 접속이 필요했다. 현재는 `InstallDRB()`가 유일한 배포 경로이며 `helm upgrade`로 전체 업데이트.

### 2. BIP44 결정론적 키 파생

```go
// DeriveDRBAccounts(mnemonic) → DRBAccounts
// leader:   BIP44 index 0 (admin key와 동일)
// regular1: index 5
// regular2: index 6
// regular3: index 7
```

`trh-sdk/pkg/stacks/thanos/drb_accounts.go`에서 `DeriveDRBAccounts()` 구현.

### 3. libp2p Ed25519 Peer ID

각 노드의 peer ID는 mnemonic에서 결정론적으로 파생. `peerIDBytes`(Ed25519 keypair)는 K8s Secret의 `data` 필드(base64)에 저장되어 `/app/static-key/leadernode.bin` 또는 `regularnode.bin`으로 마운트.

### 4. Helm `--set-string` 전략

values.yaml 기본값은 참고용. `helm upgrade`에서 리스트 요소를 일부만 override하면 나머지 필드가 초기화되므로, Go 코드에서 모든 필드를 명시적으로 `--set-string` 인자로 주입.

```go
regularPorts := []int{9601, 9602, 9603}
for i, r := range accounts.Regulars {
    prefix := fmt.Sprintf("regulars[%d]", i)
    args = append(args,
        "--set-string", fmt.Sprintf("%s.privateKey=%s", prefix, r.PrivateKey),
        "--set-string", fmt.Sprintf("%s.peerID=%s", prefix, r.PeerID),
        "--set-string", fmt.Sprintf("%s.peerIDBytes=%s", prefix,
            base64.StdEncoding.EncodeToString(r.PeerIDBytes)),
        "--set", fmt.Sprintf("%s.port=%d", prefix, regularPorts[i]),
    )
}
```

### 5. DRB는 체인 배포 후에만 설치 가능

`PluginsThatWorkWithoutChain` 맵에서 `PluginDRB` 제거. K8s 설정(`config.K8s != nil`)과 `L2RpcUrl`이 없으면 `InstallDRB()`가 명시적 에러 반환.

---

## 파일 구조

```
pkg/stacks/thanos/
  drb.go           # InstallDRB(), UninstallDRB() — 유일한 배포 경로
  drb_accounts.go  # DeriveDRBAccounts() — BIP44 + libp2p 키 파생
  drb_genesis.go   # DRB predeploy 주소 (0x4200...0060)
  drb_test.go      # 단위 테스트 (K8s nil, L2RpcUrl empty, Mnemonic empty, chart not found)
commands/
  plugins.go       # install/uninstall drb-vrf 라우팅

tokamak-thanos-stack/charts/drb-vrf/
  values.yaml
  templates/
    secret.yaml                    # K8s Secret: 개인키 + peerIDBytes
    leader-deployment.yaml
    leader-postgres-deployment.yaml
    leader-service.yaml
    regular-deployment.yaml        # range .Values.regulars → 3개 Deployment
    regular-postgres-deployment.yaml
    regular-service.yaml           # range → 3개 ClusterIP Service
```

---

## 사전 요구사항

- EKS 클러스터가 존재하고 `config.K8s`에 설정되어 있어야 함
- L2 체인이 배포되어 `config.L2RpcUrl`이 설정되어 있어야 함
- `config.Mnemonic`이 설정되어 있어야 함 (키 파생에 사용)
- `tokamak-thanos-stack` 레포가 클론되어 있어야 함 (`deploymentPath/tokamak-thanos-stack/charts/drb-vrf/` 존재)
