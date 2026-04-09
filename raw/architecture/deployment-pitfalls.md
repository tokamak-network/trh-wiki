# Domain Pitfalls

**Domain:** L1 Deposit Transaction-based CrossTrade L2 Contract Deployment for TRH Platform
**Researched:** 2026-04-07

---

## Critical Pitfalls

Mistakes that cause deployment failures, locked contracts, or require full redeployment.

### Pitfall 1: L2 Sender Address Aliasing Breaks onlyOwner on Proxy

**What goes wrong:** When an EOA calls `OptimismPortal.depositTransaction()` on L1, the L2 `msg.sender` is the EOA address **without aliasing** (aliasing only applies when a contract calls the portal). However, if the deployment logic is ever routed through an intermediary contract (e.g., a deployer helper, a multicall contract, or a future SDK contract wrapper), the L2 sender becomes `l1Address + 0x1111000000000000000000000000000000001111` -- the aliased address. The Proxy constructor grants `ADMIN_ROLE` to `msg.sender`, so all subsequent `onlyOwner` calls (setSelectorImplementations2, initialize, setChainInfo, registerToken) must come from the **exact same aliased/unaliased sender address**.

**Why it happens:** The OP Stack applies address aliasing only when `msg.sender` has code (is a contract). Developers test with EOA, then refactor to use a contract-based deployer, and suddenly Steps 3-12 fail with "Accessible: Caller is not an admin" because the proxy's admin is now the aliased address, but subsequent deposit txs still come from the unaliased EOA (or vice versa).

**Consequences:** All 4 proxy contracts are deployed but permanently locked -- no implementation can be set, no initialization is possible. The contracts must be redeployed from scratch with a fresh nonce sequence.

**Prevention:**
- Hard rule: ALL 12 deposit transactions MUST use the same L1 sender mechanism. If Step 1 (proxy creation) uses EOA, Steps 3-12 must also use EOA directly.
- Add an explicit check in `DeployCrossTradeLocal()` that the deployer address has no code: `code, _ := l1Client.CodeAt(ctx, deployerAddr, nil); require len(code) == 0`.
- Document in code comments: "DO NOT wrap these calls in a contract -- address aliasing will break admin permissions."
- Unit test: verify the L2 sender address matches expectations before proceeding to Step 3.

**Detection:** Step 3 (`setSelectorImplementations2`) reverts with "Accessible: Caller is not an admin". If you see this error, the alias mismatch has already occurred.

**Confidence:** HIGH -- verified via OP Stack spec and AccessibleCommon.sol source.

---

### Pitfall 2: L2 Nonce Desynchronization Across 12 Sequential Deposit Transactions

**What goes wrong:** The 12-step deployment sequence requires each deposit tx to execute in strict order on L2 because contract addresses from CREATE depend on `keccak256(rlp([sender, nonce]))`. If any single deposit tx fails silently on L2 (reverts but is still included in a block, incrementing the nonce), all subsequent contract addresses shift by one nonce position. Step 3 references the impl address from Step 1 and the proxy address from Step 2 -- if the proxy was created at a different address than predicted, `setSelectorImplementations2` is called on the wrong contract (or a nonexistent one).

**Why it happens:**
1. Deposit transactions are **guaranteed to be included** on L2 (they cannot be censored), but they **can revert**. A reverted deposit tx still increments the sender's L2 nonce.
2. The deployer doesn't check L2 execution status between steps -- they fire 12 L1 transactions and assume all succeed.
3. Gas estimation is wrong for one step (e.g., contract creation bytecode is larger than expected), causing an L2 out-of-gas revert that goes unnoticed.

**Consequences:** Steps 3-12 operate on wrong addresses. Proxy points to nothing or to wrong implementation. The entire deployment is silently corrupted -- contracts exist at unexpected addresses and are unusable.

**Prevention:**
- **Wait for L2 receipt after EACH deposit tx.** Do not fire Step N+1 until Step N's L2 receipt confirms `status == 1` (success). This is the most critical implementation requirement.
- Predict the L2 contract address using `crypto.CreateAddress(aliasedSender, currentNonce)` and verify it matches the address in the L2 receipt's `ContractAddress` field.
- Implement a `waitForDepositTxL2Receipt()` helper that:
  1. Gets the L1 tx receipt
  2. Extracts the deposit nonce / source hash from the `TransactionDeposited` event log
  3. Polls the L2 for the corresponding transaction receipt
  4. Verifies `receipt.Status == 1`
- Store the entire deployment state (which step completed, what addresses were created) in a state file so partial failures can be retried from the correct step.

**Detection:** Check if L2 contract addresses match predicted addresses after deployment. If they don't match, a nonce slip occurred.

**Confidence:** HIGH -- CREATE address formula is deterministic; OP Stack spec confirms deposit tx reverts still increment nonce.

---

### Pitfall 3: Gas Estimation Mismatch Between L1 Gas Limit Parameter and L2 Execution Cost

**What goes wrong:** `OptimismPortal.depositTransaction()` takes a `_gasLimit` parameter that specifies the L2 execution gas. This is NOT the L1 gas limit -- it's a value embedded in the deposit event that the L2 block derivation pipeline reads. If this value is too low, the L2 execution reverts with out-of-gas. If it's too high, the L1 transaction costs more (because the portal charges for the gas overhead). The PRD suggests a flat `3_000_000` gas for all steps, but contract creation (Steps 1, 2, 7, 8) and function calls (Steps 3-6, 9-12) have vastly different gas requirements.

**Why it happens:**
- Contract creation gas depends on bytecode size, which varies between L2CrossTrade (large, with SafeERC20 library) and L2CrossTradeProxy (smaller). Using a flat value wastes ETH or fails on large contracts.
- L2 gas costs may differ from L1 EVM expectations (though OP Stack L2 uses standard EVM gas pricing for execution, the overhead calculation differs).
- Fee token chains (USDC, USDT as fee token) have additional complexity in gas calculations.

**Consequences:** Too low = silent L2 revert (see Pitfall 2). Too high = unnecessary ETH spending on L1 (the portal doesn't refund unused L2 gas to the L1 caller).

**Prevention:**
- Measure actual gas usage for each of the 12 steps on a test deployment. Record and use per-step gas limits with a 50% safety margin.
- For contract creation steps: estimate gas as `deploymentBytecodeSize * 200 + 21000 + constructorExecutionGas`. The `200` per byte is the CREATE cost.
- For function call steps: use `eth_estimateGas` against the L2 RPC with the aliased/unaliased sender address to get accurate estimates, then add 30% margin.
- Never use a single flat gas value for all 12 steps.

**Detection:** Monitor L1 transaction costs. If they're significantly higher than expected, gas limits may be over-padded. If L2 transactions revert, gas limits are too low.

**Confidence:** HIGH -- OptimismPortal ABI confirms `_gasLimit` is L2 execution gas, not L1 gas.

---

### Pitfall 4: Proxy setSelectorImplementations2 Requires Exact Function Selector List

**What goes wrong:** After deploying the implementation contract (L2CrossTrade) and proxy (L2CrossTradeProxy), Step 3 calls `proxy.setSelectorImplementations2(selectors, implAddress)`. This requires:
1. The implementation address to be registered as "alive" via `setImplementation2` or `upgradeTo` FIRST.
2. An exact list of function selectors (`bytes4[]`) matching the implementation contract's external functions.

If selectors are missing, those functions won't route through the proxy. If wrong selectors are included, `setSelectorImplementations2` will succeed but the proxy will delegatecall to wrong code. The Proxy.sol code also explicitly rejects duplicate selector-implementation mappings: `require(selectorImplementation[_selectors[i]] != _imp, "LiquidityVaultProxy: same imp")`.

**Why it happens:**
- Developers hardcode a selector list from one version of L2CrossTrade.sol, then the contract is updated with new functions. The selector list becomes stale.
- Missing step: the proxy requires `upgradeTo(implAddress)` or `setImplementation2(implAddress, 0, true)` before `setSelectorImplementations2` can be called (because `aliveImplementation[_imp]` must be true).
- The PRD's 6-step sequence shows Step 3 as `setSelectorImplementations2` but doesn't mention the prerequisite `upgradeTo` call. This is actually an implicit Step 2.5 or is handled by the Proxy constructor setting `proxyImplementation[0]` -- but only if `upgradeTo` is called first.

**Consequences:** Proxy is deployed but all CrossTrade function calls (`requestRegisteredToken`, `claimCT`, etc.) revert with "Proxy: impl OR proxy is false" because no alive implementation routes the selectors.

**Prevention:**
- Add an explicit `upgradeTo(implAddress)` deposit tx between proxy creation and `setSelectorImplementations2`. This changes the 6-step sequence to 7 steps per contract pair (14 total, not 12).
- Generate the selector list programmatically from the contract ABI at build time, not hardcoded. Use `abi.Methods` from go-ethereum's ABI parser.
- After deployment, call a known function (e.g., `saleCount()`) through the proxy to verify routing works.

**Detection:** Any function call to the proxy address returns "Proxy: impl OR proxy is false". Test by calling a view function after deployment.

**Confidence:** HIGH -- verified from Proxy.sol source code: `setSelectorImplementations2` checks `aliveImplementation[_imp]`.

---

### Pitfall 5: setChainInfo Permission Model -- L2 vs L1 Owner Key Confusion

**What goes wrong:** There are TWO different `setChainInfo` calls in the deployment flow, easily confused:

1. **L2 setChainInfo** (Steps 5 and 11): Called on the L2 proxy contracts via deposit tx. Sets `chainData[l1ChainId] = l1CrossTradeAddress` on L2. The caller must be the proxy's admin (the L2 sender of the deposit tx = deployer EOA).

2. **L1 setChainInfo** (Backend post-deploy): Called on the existing L1 CrossTrade contracts. Sets chain registration data on L1. The caller must be the L1 contract's existing owner (whoever deployed the L1 contracts originally).

The PRD says "L1 setChainInfo is Backend responsibility, SDK handles L2 only." But the L1 owner key might differ from the deployer key. On Sepolia they're the same (simplification), but this assumption breaks if:
- The L1 CrossTrade contracts were deployed by a different team/key
- The deployer key doesn't have ADMIN_ROLE on the L1 contracts
- Multi-sig or timelock is the L1 owner

**Why it happens:** Phase 1 simplifies by using `deployer == l1Owner`. When this assumption is lifted for mainnet, the Backend suddenly needs a separate key management path for L1 setChainInfo, which may not even be an EOA.

**Consequences:** L2 contracts are deployed successfully, but L1 registration fails. CrossTrade is non-functional because L1 doesn't recognize the new L2 chain.

**Prevention:**
- In the `CrossTradeL1RegistrationInput` struct, make `L1OwnerPrivateKey` a separate field (not reusing `DeployerPrivateKey`). Even in Phase 1, keep them logically separate so the code path is ready for mainnet.
- Before calling L1 setChainInfo, verify the key has admin role: `isAdmin(senderAddress)` call on the L1 contract.
- Add a pre-flight check in the Backend: query `L1CrossTradeProxy.isAdmin(ourAddress)` before attempting `setChainInfo`. Fail fast with a clear error message.
- Document the assumption: "Phase 1: deployer == L1 owner. Phase 2: separate key management required."

**Detection:** L1 setChainInfo tx reverts with "Accessible: Caller is not an admin". Check the L1 contract's admin list.

**Confidence:** HIGH -- verified from AccessibleCommon.sol `onlyOwner` modifier and PRD Key Decision #3.

---

## Moderate Pitfalls

### Pitfall 6: Go Module Pseudo-Version Dependency Between trh-backend and trh-sdk

**What goes wrong:** trh-backend imports trh-sdk via Go module with a pseudo-version (`v1.0.5-0.20260404131108-0e7d5eacc018`). When adding `DeployCrossTradeLocal()` to trh-sdk, the backend cannot use it until:
1. The SDK change is committed and pushed to a branch
2. Backend's `go.mod` is updated with `go get github.com/tokamak-network/trh-sdk@<commit-hash>`
3. The pseudo-version is regenerated

This creates a chicken-and-egg problem during development: you can't test backend integration until SDK is committed, but you can't validate the SDK interface without backend integration.

**Why it happens:** Go modules require published commits for cross-repo imports. There's no "local development" mode by default. Developers try `replace` directives but forget to remove them before committing, or they push a `go.mod` with a `replace` directive pointing to a local path.

**Prevention:**
- Use `go.mod` `replace` directive for local development ONLY:
  ```
  replace github.com/tokamak-network/trh-sdk => /Users/theo/workspace_tokamak/trh-sdk
  ```
- Add a CI check that rejects any `go.mod` containing `replace` directives pointing to local paths.
- Development workflow: SDK changes first, push to feature branch, then `go get github.com/tokamak-network/trh-sdk@feature-branch-commit` in backend.
- Consider creating the SDK interface (types + function signature) first as a PR, merge it, then implement backend consumer code against the real import.

**Detection:** `go build` fails with "unknown revision" or "module not found". Or worse: CI passes with local `replace` but fails in production Docker build.

**Confidence:** HIGH -- verified from current `go.mod` showing pseudo-version pattern.

---

### Pitfall 7: Deposit Tx L2 Receipt Polling -- Wrong Transaction Mapping

**What goes wrong:** After sending a deposit transaction on L1, you need to find the corresponding L2 transaction to check its receipt. The mapping is NOT trivial:
- L1 tx hash != L2 tx hash (they are completely different)
- The L2 transaction hash is derived from the deposit's `sourceHash`, which is computed from the L1 block number, L1 log index, and deposit nonce
- If you poll `eth_getTransactionReceipt` with the L1 tx hash against the L2 RPC, you get nothing (or worse, an unrelated tx)

**Why it happens:** Developers assume L1 tx hash == L2 tx hash, or try to find the L2 tx by sender + nonce, which can match a wrong transaction if the nonce accounting is off.

**Prevention:**
- Parse the `TransactionDeposited` event from the L1 receipt to extract `opaqueData`
- Compute the L2 deposit tx hash using the OP Stack formula: `sourceHash = keccak256(bytes32(uint256(0)), keccak256(l1BlockHash, uint256(logIndex)))`
- Use `eth_getTransactionByHash(depositTxHash)` on L2 with the computed hash
- Alternative: use `optimism_getDepositReceipt` if available on the L2 node
- Implement a polling loop with exponential backoff (deposit txs can take 1-2 L2 blocks to be included)

**Detection:** `waitForDepositTxL2Receipt()` times out or returns the wrong receipt. Always verify the receipt's `from` field matches the expected aliased/unaliased deployer address.

**Confidence:** MEDIUM -- OP Stack spec documents the source hash computation, but the exact Go implementation requires testing against a live L2 node.

---

### Pitfall 8: Docker Compose Conditional Service -- CrossTrade dApp Starts Before Contracts Are Deployed

**What goes wrong:** The CrossTrade dApp container is defined in `docker-compose.yml` with `depends_on: backend`. It starts as soon as the backend container is healthy. But the dApp needs environment variables (contract addresses, chain config JSON) that are only available AFTER the L2 deployment AND CrossTrade contract deployment are complete. If the dApp starts before contracts are deployed, it shows broken/empty UI or crashes on missing config.

**Why it happens:** Docker Compose `depends_on` only waits for container start (or healthcheck), not for application-level readiness. The CrossTrade deployment is a post-deploy step that runs minutes after the backend is healthy.

**Prevention:**
- Do NOT include the CrossTrade dApp in the initial `docker-compose.yml`. Instead, start it separately after CrossTrade deployment completes:
  ```bash
  docker compose --profile crosstrade up -d crosstrade-dapp
  ```
  Use Docker Compose profiles to make the service opt-in.
- Alternative: use `docker compose up crosstrade-dapp` as a separate command triggered by the Backend after contract deployment succeeds.
- The dApp should have a health endpoint that returns unhealthy until it can verify contract addresses are valid.
- Write the `.env.crosstrade` file from Backend only after successful deployment, and mount it as the dApp's env source.

**Detection:** CrossTrade dApp shows "Contract not found" errors or blank pages immediately after deployment. Check if `.env.crosstrade` exists and contains valid addresses.

**Confidence:** HIGH -- standard Docker Compose timing issue, verified from current `docker-compose.yml` pattern.

---

### Pitfall 9: L2CrossTrade Constructor Initializes ReentrancyGuard BUT Proxy Delegates, Not Inherits

**What goes wrong:** L2CrossTrade inherits `ReentrancyGuard` and its constructor sets `_status = 1` (NOT_ENTERED). However, when the proxy delegates calls to the implementation, the storage slot for `_status` lives in the proxy's storage, not the implementation's. The implementation's constructor initialized `_status` in the implementation's own storage during CREATE -- which is never used because all calls go through the proxy.

This means the proxy's `_status` slot is uninitialized (default = 0). When `nonReentrant` modifier checks `_status`, it expects `1` (NOT_ENTERED) but finds `0`. Depending on the ReentrancyGuard implementation, this may:
- Revert on first call (OpenZeppelin v4+ uses `_status == _NOT_ENTERED` check)
- Allow reentrancy (if the guard checks `_status != _ENTERED` where `_ENTERED = 2`)

**Why it happens:** The PRD says "constructor executes ReentrancyGuard initialization automatically" -- this is true for the implementation's own storage, but irrelevant for the proxy pattern where delegatecall uses the proxy's storage context.

**Consequences:** Either all `nonReentrant` functions revert permanently, or reentrancy guard doesn't work (security vulnerability).

**Prevention:**
- Check the specific ReentrancyGuard implementation used by CrossTrade contracts. If it's OpenZeppelin-style where `_NOT_ENTERED = 1`, you need an `initialize()` function on the proxy that sets `_status = 1` in the proxy's storage.
- Alternatively, if the ReentrancyGuard uses `_NOT_ENTERED = 0` (checking for `_status == 2` as entered), the default zero value works correctly and no initialization is needed.
- Read the actual `ReentrancyGuard.sol` source in the crossTrade contracts to determine which pattern is used.
- **Test this explicitly**: after deployment, call `requestRegisteredToken` through the proxy. If it reverts with a reentrancy error, the guard's storage needs initialization.

**Detection:** First call to any `nonReentrant` function (requestRegisteredToken, claimCT, cancelCT) fails unexpectedly.

**Confidence:** MEDIUM -- depends on the specific ReentrancyGuard implementation. Needs verification against the actual `contracts/utils/ReentrancyGuard.sol`.

---

### Pitfall 10: registerToken Step Requires L2 Token Addresses That May Not Exist Yet

**What goes wrong:** Step 6 (and Step 12 for L2toL2) calls `registerToken(l1Token, l2Token, l1ChainId)` to pre-register ETH, USDC, USDT pairs. The L2 token addresses (bridged USDC, bridged USDT) are predeploys or genesis-deployed addresses that depend on the specific L2 chain configuration. If the deployer uses wrong L2 token addresses (e.g., from a different chain or from documentation), the token registration succeeds but CrossTrade requests for those tokens will fail because the registered addresses don't match actual L2 token contracts.

**Why it happens:**
- L2 predeploy addresses differ between fee token types (ETH fee vs USDC fee vs USDT fee chains)
- The USDC and USDT addresses on L2 may be bridged tokens (BridgedUSDC) or native tokens, with different addresses
- Copy-paste from Sepolia testnet values to mainnet or vice versa

**Prevention:**
- Read L2 token addresses from the deployment output / genesis config programmatically, never hardcode them.
- Cross-reference with the L2's `L2StandardBridge` predeploy to verify token mappings.
- Add a post-registration verification: for each registered pair, call `registerCheck[chainId][l1Token][l2Token]` on the deployed contract to confirm it returns true.

**Detection:** CrossTrade requests fail with "CT: The tokens are not registered" even though `registerToken` was called.

**Confidence:** HIGH -- verified from L2CrossTrade.sol `requestRegisteredToken` which checks `registerCheck[_l1chainId][_l1token][_l2token] == true`.

---

## Minor Pitfalls

### Pitfall 11: L1 Transaction Nonce Race Condition During Sequential Deposit Txs

**What goes wrong:** The deployer sends 12 L1 transactions in sequence. If the Go code uses `PendingNonceAt()` for each transaction, and L1 blocks are slow (12-15 seconds on Sepolia), multiple deposit txs may try to use the same L1 nonce because the previous tx hasn't been mined yet.

**Prevention:**
- Manually track the L1 nonce in the SDK code. Fetch it once at the start (`PendingNonceAt`), then increment locally for each subsequent transaction.
- Do NOT call `PendingNonceAt` before each transaction -- use local counter.
- Set reasonable gas prices to ensure L1 inclusion within 1-2 blocks.

**Detection:** L1 transactions fail with "nonce too low" or "replacement transaction underpriced".

---

### Pitfall 12: Backend `localUnsupported` Map Removal Creates Implicit Feature Flag

**What goes wrong:** Removing `crossTrade` from `localUnsupported` map enables CrossTrade for ALL local deployments with DeFi/Full preset. But the actual deployment code might not be ready yet, causing runtime errors for users who deploy before the SDK implementation is complete.

**Prevention:**
- Don't remove from `localUnsupported` until the full pipeline (SDK + Backend + dApp) is tested E2E.
- Consider a versioned feature flag instead of removing the entry: `localUnsupported["crossTrade"] = sdkVersion < requiredVersion`.
- Gate the feature behind a check that `DeployCrossTradeLocal` is actually implemented (not returning nil placeholder).

**Detection:** Local DeFi preset deployment starts CrossTrade integration and immediately fails with nil pointer or "not implemented" error.

---

### Pitfall 13: L2toL2CrossTrade setChainInfo Has Different Parameters Than L2CrossTrade setChainInfo

**What goes wrong:** The L2->L1 `setChainInfo` takes `(address _l1CrossTrade, uint256 _chainId)`, but the L2->L2 version (L2toL2CrossTradeProxy) likely has a different signature with additional parameters (bridge, usdcBridge, nativeToken). Using the same ABI encoding for both will cause the deposit tx to revert silently on L2.

**Prevention:**
- Generate separate ABI bindings for L2CrossTradeProxy and L2toL2CrossTradeProxy.
- Verify the function signatures from the actual ABI files before encoding deposit tx data.
- Test each contract pair's initialization sequence independently.

**Detection:** L2toL2 setChainInfo deposit tx reverts on L2 while L2toL1 succeeds, or vice versa.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation | Priority |
|-------------|---------------|------------|----------|
| SDK: DeployCrossTradeLocal implementation | #1 (Address Aliasing), #2 (Nonce Desync), #3 (Gas Estimation) | Sequential execution with L2 receipt verification per step | Phase 1 - MUST |
| SDK: Contract address prediction | #2 (Nonce), #4 (Selector list) | Pre-compute addresses, verify against L2 receipts | Phase 1 - MUST |
| SDK: Proxy initialization sequence | #4 (Missing upgradeTo), #9 (ReentrancyGuard storage) | Add upgradeTo step, verify ReentrancyGuard impl | Phase 1 - MUST |
| Backend: L1 setChainInfo | #5 (Owner key confusion) | Separate key fields, pre-flight admin check | Phase 1 - MUST |
| Backend: SDK integration | #6 (Go module pseudo-version) | replace directive workflow, CI guard | Phase 1 - HIGH |
| Backend: Token registration | #10 (Wrong L2 addresses) | Read from deployment output, post-verify | Phase 1 - HIGH |
| Platform: dApp container | #8 (Premature start) | Docker Compose profiles, delayed start | Phase 2 - MEDIUM |
| Platform: Feature gating | #12 (Implicit feature flag) | Version check before enabling | Phase 1 - MEDIUM |
| SDK: L1 nonce management | #11 (Nonce race) | Local nonce counter | Phase 1 - MEDIUM |
| SDK: L2toL2 ABI differences | #13 (Parameter mismatch) | Separate ABI bindings | Phase 1 - MEDIUM |

---

## Sources

- [OP Stack Deposits Specification](https://specs.optimism.io/protocol/deposits.html) -- deposit tx format, address aliasing rules, nonce behavior
- [OP Stack Differences from Ethereum](https://docs.optimism.io/stack/differences) -- address aliasing for contract vs EOA callers
- [Optimism Address Aliasing Discussion](https://github.com/ethereum-optimism/optimism/discussions/1480) -- msg.sender / tx.origin behavior for L1->L2
- [RareSkills: Ethereum Address Derivation](https://rareskills.io/post/ethereum-address-derivation) -- CREATE address formula: `keccak256(rlp([sender, nonce]))`
- CrossTrade contracts source: `Proxy.sol`, `AccessibleCommon.sol`, `L2CrossTrade.sol`, `L2CrossTradeProxy.sol` -- verified admin/owner patterns
- `trh-sdk/pkg/stacks/thanos/cross_trade.go` -- existing AWS deployment patterns, no nonce management (Foundry handles it)
- `trh-backend/go.mod` -- current pseudo-version dependency on trh-sdk
- PRD v2.1 -- 12-step deployment sequence, feature architecture
