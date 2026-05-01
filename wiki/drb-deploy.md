---
updated: 2026-05-01
---

# DRB Node Deployment (trh-sdk)

DRB leader/regular 노드를 AWS에 배포하는 trh-sdk 구현 설계 결정.

---

## CLI 진입점

```bash
trh-sdk install drb-vrf --type leader   # EKS + Terraform
trh-sdk install drb-vrf --type regular  # EC2 직접 배포
trh-sdk drb info                        # leader 배포 정보 출력 (drb-leader-info.json)
```

**주의**: `PluginDRB` 상수값은 `"drb-vrf"` (main 브랜치 기준). `"drb"`는 구버전 이름이며 더 이상 유효하지 않음.

---

## 핵심 설계 결정

### 1. PluginDRB 상수값 = `"drb-vrf"`
- `pkg/constants/plugins.go`에서 `PluginDRB = "drb-vrf"`
- Helm chart 이름(`drb-vrf`)과 일치시켜 명명 (비록 신규 DRB는 Terraform/EC2 방식이지만)
- 과거 PR에서 `"drb"`로 변경됐다가 main 정렬을 위해 `"drb-vrf"`로 복원

### 2. 외부 레포 브랜치 고정
| 레포 | 브랜치 | 이유 |
|------|--------|------|
| `tokamak-thanos-stack` | `feat/add-drb-node` | `main`에 `terraform/drb` 디렉토리 없음 |
| `DRB-node` | `dispute-mechanism` | `main`과 동일 파일 구성이지만 기존 코드 일관성 유지 |

→ 두 레포의 `main` 브랜치가 DRB 코드를 포함하게 되면 브랜치 ref 교체 필요.

### 3. Leader 노드: EKS + Terraform
- `drb_leader.go` (~1500 lines): Terraform init/apply로 EKS 클러스터 생성
- `drb-leader-info.json` 파일에 배포 결과 기록 (URL, peer ID, contract 주소 등)
- `trh-sdk drb info` 명령으로 조회 가능

### 4. Regular 노드: EC2 직접 배포
- `drb_regular.go` (~700 lines): AWS CLI로 EC2 인스턴스 직접 생성
- User-data 스크립트에 base64 인코딩된 env 포함 (EOA_PRIVATE_KEY 포함)
- 파일 권한: user-data 스크립트 `0600`, env 파일 `0600`

---

## 보안 결정 사항

### SSH 보안 그룹 CIDR
- `createRegularNodeSecurityGroup()`에서 SSH(22) inbound 규칙 설정
- `checkip.amazonaws.com`으로 배포자 공인 IP 자동 조회 → `/32` CIDR 적용
- IP 조회 실패 시 `0.0.0.0/0` 폴백 (배포 중단 방지)

### User-data 파일 권한
- `drb-regular-user-data.sh` (base64 EOA_PRIVATE_KEY 포함) → `0600`
- `.envrc` (S3 버킷 이름 등 비밀 아닌 설정) → `0644` 유지

### Base64 Heredoc 인젝션
- `buildRegularNodeUserData()`에서 env 내용을 base64로 인코딩하여 heredoc 인젝션 방지
- `base64.StdEncoding.EncodeToString()` 사용

---

## 파일 구조

```
pkg/stacks/thanos/
  drb.go            # 구버전 Helm 기반 DRB VRF (uninstall 시 참조)
  drb_leader.go     # EKS leader 노드 배포
  drb_regular.go    # EC2 regular 노드 배포
commands/
  drb.go            # trh-sdk drb info 명령 구현
  plugins.go        # install/uninstall drb-vrf 라우팅
```

---

## 알려진 제약

- `tokamak-thanos-stack`의 `feat/add-drb-node` 브랜치가 `main`에 머지될 때까지 하드코딩 유지 필요
- DRB-node `dispute-mechanism` 브랜치도 마찬가지
- Regular 노드 배포 후 SSH 접속은 배포 시점의 공인 IP로만 가능 (IP 변경 시 SG 수동 업데이트 필요)
