---
updated: 2026-04-09
sources:
  - raw/architecture/tech-stack.md
related:
  - "[[trh-platform]]"
  - "[[l2-deployment]]"
  - "[[aws-sso]]"
tags: [concept]
---

# Keystore

trh-platform Electron 앱의 시드 구문 저장 및 키 파생 시스템.

---

## 저장 방식

Electron `safeStorage` API → OS 키체인 암호화 (macOS Keychain / Windows DPAPI / Linux libsecret)

- 평문 니모닉은 메모리에만 존재, 디스크에는 암호화 형태로 저장
- 파생된 개인키는 절대 webview에 주입하지 않음 (주소만 전달)

---

## 키 파생 (BIP44)

ethers `HDNodeWallet` 사용:

```
Seed Phrase (BIP39)
    └── BIP44 HD 파생
         ├── m/44'/60'/0'/0/0  → Admin key    (L1 컨트랙트 owner)
         ├── m/44'/60'/0'/0/1  → Batcher key  (op-batcher)
         ├── m/44'/60'/0'/0/2  → Proposer key (op-proposer)
         └── m/44'/60'/0'/0/3  → Deployer key (CrossTrade 등)
```

---

## IPC 인터페이스

`window.electronAPI`를 통해 renderer에서 호출:

| 함수 | 설명 |
|------|------|
| `storeSeedPhrase(mnemonic)` | BIP39 검증 후 암호화 저장 |
| `hasSeedPhrase()` | 저장 여부 확인 |
| `deleteSeedPhrase()` | 키체인에서 삭제 |
| `getAddresses()` | 파생 주소 반환 (키 미노출) |
| `deriveKeysToEnv()` | 개인키 → Docker env 주입 (메모리 내) |

---

## 보안 원칙

- `contextIsolation: true`, `sandbox: true` (preload)
- 외부 네트워크 요청 차단 (network-guard) → [[trh-platform]]
- 니모닉 유효성: BIP39 `validateMnemonic()` 통과 시에만 저장
