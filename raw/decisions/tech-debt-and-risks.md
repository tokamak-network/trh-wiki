# Codebase Concerns

**Analysis Date:** 2026-04-09

## Tech Debt

**Hardcoded localhost backend URL:**
- Issue: Electron app hardcodes `http://localhost:3000` and `http://localhost:8000` with no remote server configuration option
- Files: `src/main/webview.ts:17-18`, `src/main/index.ts:70`
- Impact: Desktop app only works with local Docker setup; cannot point to remote backend for testing or cloud deployments
- Fix approach: Add environment variable support (`BACKEND_API_URL`, `PLATFORM_UI_URL`) read at startup, with fallback to localhost for development

**WebContentsView sandbox:false:**
- Issue: WebView preload requires `sandbox: false` for IPC communication
- Files: `src/main/webview.ts:98`
- Impact: Preload can access full Node.js APIs; slight security reduction vs fully sandboxed renderer
- Fix approach: Consider sandboxed context bridge pattern if future Electron versions support it; currently necessary for credentials injection
- Status: Intentional trade-off documented in code comment

**Network guard silently allows on parse failure:**
- Issue: Invalid URLs during network guard checks silently allow requests instead of blocking
- Files: `src/main/network-guard.ts:87-89`
- Impact: Malformed URLs bypass security checks; low risk due to whitelisting approach, but could mask bugs
- Fix approach: Log blocked/error cases for debugging; consider denying on parse failure instead of allowing

**Credentials stored in module scope (AWS, Admin):**
- Issue: AWS credentials and admin login credentials cached in memory in `aws-auth.ts` and `webview.ts` module scope
- Files: `src/main/aws-auth.ts:50`, `src/main/webview.ts:25`
- Impact: Long-running app keeps sensitive data in memory; potential exposure if process memory is accessed
- Fix approach: Add credential expiration timer (e.g., 60min for AWS, 30min for admin); clear on logout
- Status: Partially mitigated — AWS credentials include expiresAt field but not actively cleared on expiry

## Known Bugs

**Docker container health check with 3+ container expectation:**
- Issue: `getDockerStatus()` checks `containers.length >= 3` but doesn't account for optional services (CrossTrade dApp)
- Files: `src/main/docker.ts:334`
- Impact: When CrossTrade dApp is disabled, health check may incorrectly report unhealthy status if only 2 containers running
- Trigger: Deploy General or Gaming preset (no CrossTrade dApp); containers show as "not up" even if healthy
- Workaround: None currently; may require preset-aware container count logic
- Fix approach: Read enabled services from Docker Compose dynamically instead of hardcoding count

**Mnemonic decryption buffer fill (incomplete cleanup):**
- Issue: `deriveKeysToEnv()` fills mnemonic buffer with zeros, but private keys remain in memory in env object
- Files: `src/main/keystore.ts:120`
- Impact: Keys derived from mnemonic are cleared from mnemonic buffer only; derived private key strings still in heap
- Workaround: Keys cleared from buffer but not from returned env object
- Fix approach: Wrapper utility to clear env object after use; or use Buffer-based key storage
- Status: Low risk — keys are passed through IPC and not persisted, but cleanup is incomplete

**Type assertion on Docker error (errorType attachment):**
- Issue: Code attaches custom `errorType` property to Error object via `(err as any)` cast
- Files: `src/main/docker.ts:600-602`
- Impact: Type-unsafe; no IDE/compiler checking for errorType property usage downstream
- Workaround: Code path works but brittle
- Fix approach: Create custom Error subclass `DockerError extends Error { errorType: string; output?: string }`

**Stale container names hardcoded:**
- Issue: Force-remove uses hardcoded container names that may not reflect actual project setup
- Files: `src/main/docker.ts:683-684`
- Impact: If user customizes docker-compose.yml or project names, cleanup may fail to remove their stale containers
- Workaround: Manual `docker rm -f` required
- Fix approach: Parse docker-compose.yml to get actual service names before cleanup

## Missing Error Handling

**WebView navigation to unreachable backend:**
- Issue: If backend becomes unreachable after platform view loads, no error is shown
- Files: `src/main/webview.ts:128-150` (did-navigate handler)
- Impact: User sees blank page with no indication that backend is down
- Fix approach: Add connectivity check on navigation; show in-app toast if backend is unreachable

**IPC handler errors not validated:**
- Issue: IPC handlers assume valid input; no validation of message payloads from renderer
- Files: `src/main/index.ts:642-648` (keystore IPC handlers)
- Impact: Malformed input could cause unhandled promise rejections in main process
- Fix approach: Add zod schema validation for all IPC input payloads

**Docker pull timeout (10 min) not configurable:**
- Issue: Image pull has fixed 600s timeout; slow networks may exceed this
- Files: `src/main/docker.ts:10, 400-402`
- Impact: Large Docker images on slow networks cause timeout failure
- Fix approach: Make timeout configurable via environment variable with sensible default

**Fetch timeout in `app:load-platform` has no max timeout on total duration:**
- Issue: Retries for 10 iterations × 1s delay = 10s per retry, max 100s total; retry loop has 5s per attempt timeout
- Files: `src/main/index.ts:569-590`
- Impact: If backend is completely down, app waits ~100s before showing error (poor UX)
- Fix approach: Reduce retry count or add exponential backoff; show "still waiting" indicator

## Untested Code Paths

**Network guard edge cases:**
- Files: `src/main/network-guard.ts`
- What's not tested: URL parsing errors, dynamicHosts addition/removal, blocked request log rotation at MAX_BLOCKED_LOG
- Risk: Network request interception may fail silently in error conditions
- Priority: Medium — affects security posture

**AWS auth INI parser edge cases:**
- Files: `src/main/aws-auth.ts:68-94`
- What's not tested: Multiline values, quoted values, special characters in keys/values
- Risk: Credentials file parsing could fail or misparse complex configs
- Workaround: Works for standard AWS credentials format; fails on non-standard formats
- Priority: Low — AWS SDK provides alternative parsing, but this custom parser is simpler

**Concurrent Docker operations with dockerOperationInProgress flag:**
- Files: `src/main/index.ts:64, 200-206, 241-244` (tray menu handler concurrency)
- What's not tested: Race conditions if tray menu clicks happen while flag is set; flag timing between steps
- Risk: Two concurrent Docker operations could start if flag not properly synchronized
- Workaround: Flag appears to be synchronous; only one main thread process
- Priority: Low — single-threaded Electron main process prevents concurrent execution

**Keystore encryption availability fallback:**
- Files: `src/main/keystore.ts:45-47`
- What's not tested: `safeStorage.encryptString()` failure modes; what happens if OS keychain becomes unavailable mid-session
- Risk: Key corruption if encryption fails; no recovery mechanism
- Workaround: Throws error immediately on encryption failure
- Priority: Medium — cryptographic operation failure is critical

**WebView preload token injection retry logic:**
- Files: `src/main/webview.ts:269-288` (injectTokenToView)
- What's not tested: Max 10 retries × 100ms = 1s total; what if token never becomes available
- Risk: Token injection silently fails after 1s; no error indication
- Priority: Medium — affects auto-login feature

## Security Concerns

**Network guard whitelist allows arbitrary docker.io and github.com subdomains:**
- Issue: Pattern `/\.docker\.io$/` matches any subdomain under docker.io (e.g., `attacker.docker.io` if attacker owns it)
- Files: `src/main/network-guard.ts:15-27`
- Impact: Low risk — subdomain attacker would need to own the domain; legitimate Docker registries are safety verified by image signing
- Recommendation: Whitelist specific registries (e.g., `index.docker.io`, `auth.docker.io`) instead of all `*.docker.io`

**Admin credentials passed unsecured through IPC:**
- Issue: Admin email/password sent via IPC from renderer without encryption
- Files: `src/main/index.ts:492-502` (docker:start handler), `src/renderer/App.tsx` (renderer side)
- Impact: Credentials visible in Electron DevTools if opened; low risk since app is local-only and user controls all code
- Recommendation: For production, use secure Electron context bridge with encryption; acceptable for development/testing

**Mnemonic preview exposed via IPC without rate limiting:**
- Issue: `keystore:preview-addresses` can be called repeatedly to derive addresses from any mnemonic
- Files: `src/main/index.ts:646`
- Impact: No protection against brute-force mnemonic guessing via the IPC interface
- Recommendation: Add rate limiting (1 request per second) or move to renderer-only computation using ethers.js

**Local certificate errors allowed for localhost:**
- Issue: WebView and main window accept self-signed certificates for localhost
- Files: `src/main/webview.ts:115-125`, `src/main/index.ts:752-762`
- Impact: Correct behavior for development; acceptable since connection is already over localhost
- Status: Intentional and documented

## Performance Bottlenecks

**Docker image pull blocks UI for up to 10 minutes:**
- Problem: `pullImages()` spawns `docker compose pull` with no progress chunking; large images may show no feedback
- Files: `src/main/docker.ts:383-449`
- Cause: Progress callback only fires when stdout data arrives; large layers may batch output
- Improvement path: Parse Docker pull output in real-time with `--verbose` flag for per-layer progress

**Health check polling every 3 seconds with 120s timeout:**
- Problem: Blocks UI thread during wait; 40 polling intervals may feel slow
- Files: `src/main/docker.ts:9, 696-722`
- Cause: Synchronous polling loop without debouncing
- Improvement path: Use Docker event stream (`docker events`) instead of polling; reduces CPU and latency

**Stale container cleanup force-removes all containers regardless of project:**
- Problem: Kills unrelated Docker containers with matching names (e.g., if user has other `trh-postgres` elsewhere)
- Files: `src/main/docker.ts:683-691`
- Cause: Uses container name matching without project isolation
- Improvement path: Use `--project` flag with docker-compose to scope operations

**Auth token fetch blocks showPlatformView() call:**
- Problem: If Backend is slow, platform view shows blank screen while waiting for token
- Files: `src/main/webview.ts:63-78, 87`
- Cause: Sequential fetch before view creation
- Improvement path: Create view immediately, fetch token in background; show loading state if token missing

## Fragile Areas

**Docker Compose file path resolution:**
- Files: `src/main/docker.ts:72-81`
- Why fragile: Path logic differs between packaged and development modes; easy to break with directory restructuring
- Safe modification: Test both `npm run dev` and `npm run package` after changing paths
- Test coverage: No unit tests for path logic; must manually test both modes
- Risk: High — path misconfiguration causes "Docker Compose file not found" errors that block entire app

**Tray menu state sync with update availability:**
- Files: `src/main/index.ts:196-210, 377-419` (updateAvailable flag + tray menu rebuild)
- Why fragile: updateAvailable flag used in multiple places (tray menu, notification, banner); state can drift
- Safe modification: Centralize update state in a single source of truth; add unit tests for state transitions
- Test coverage: No unit tests; manual testing required
- Risk: Medium — update notifications can show while update is in progress

**Port conflict detection with lsof/netstat fallback:**
- Files: `src/main/docker.ts:95-114`
- Why fragile: Depends on external tools (`lsof`, `netstat`) that may not exist on all systems or may behave differently
- Safe modification: Test on Windows (uses different port checking), macOS, and Linux before deploying
- Test coverage: No unit tests; integration tests with real ports needed
- Risk: High on Windows — `lsof` doesn't exist; fallback to net.Server might not catch all cases

## Scaling Limits

**Notification store unbounded array growth:**
- Current capacity: 100 notifications max (rotation strategy)
- Files: `src/main/notifications.ts` (reference only, not shown)
- Impact: Memory use is O(1) — capped at 100 entries
- Limit: None (by design)

**Docker operation mutex (single queue):**
- Current capacity: 1 concurrent operation at a time
- Files: `src/main/index.ts:64`
- Impact: User cannot pull images while containers are starting; blocking behavior
- Scaling path: Implement operation queue with concurrent limit > 1; currently acceptable for single-user desktop app

**WebView preload script injection on every navigation:**
- Current capacity: Injects keystore/AWS creds on every page load
- Files: `src/main/webview.ts:136-150`
- Impact: Decrypts keystore on every navigation; for 100+ navigations, noticeable latency
- Scaling path: Cache injected values if no page reload; inject once per session

## Dependencies at Risk

**@aws-sdk versions (3.1013.0) pinned to old release:**
- Risk: AWS SDK v3.1013.0 (from early 2024) may have security vulnerabilities or missing features
- Impact: App may not work with newer AWS features (e.g., new credential formats, region endpoints)
- Migration plan: Update to latest v3.x with compatibility testing for AWS profile loading
- Priority: Medium — currently works but will diverge from AWS SDK stability fixes

**ethers v6 hard dependency on exact pattern:**
- Risk: `ethers@6.13.4` is strict; future projects may need v7 which has breaking changes
- Impact: Can't upgrade without rewriting address/wallet derivation code
- Migration plan: Add abstraction layer for wallet operations; support both v6 and v7 simultaneously if needed
- Priority: Low — v6 is stable and will be supported for years

**Electron 33 — relatively new major version:**
- Risk: Breaking changes in Electron major versions every 4 months
- Impact: WebContentsView API may change; preload isolation model may shift
- Migration plan: Monitor Electron releases; test new major versions early
- Priority: Low — currently stable; upgrade cycle manageable

## Test Coverage Gaps

**Electron main process (docker.ts, aws-auth.ts, keystore.ts):**
- What's not tested: Error recovery paths, timeout behaviors, concurrent operation safety
- Files: `src/main/docker.ts`, `src/main/aws-auth.ts`, `src/main/keystore.ts`
- Risk: Critical Docker operations (pull, start, stop) have minimal unit test coverage
- Improvement: Add vitest unit tests with mocked child_process and fs modules
- Priority: High — affects core functionality

**IPC communication contract validation:**
- What's not tested: Invalid IPC payloads, type mismatches, missing required fields
- Files: `src/main/index.ts:421-682` (all ipcMain.handle calls)
- Risk: Malformed IPC messages could crash main process
- Improvement: Add zod schema validation on all IPC inputs with test matrix
- Priority: High — affects stability

**WebContentsView lifecycle:**
- What's not tested: View creation/destruction, bounds updates on resize, navigation edge cases
- Files: `src/main/webview.ts`
- Risk: Memory leaks from not properly cleaning up WebContentsView; bounds miscalculation on window resize
- Improvement: Add lifecycle tests; verify bounds after each window size change
- Priority: Medium — affects long-running stability

**Network guard URL patterns:**
- What's not tested: Edge cases like internationalized domain names, ports in URLs, query strings
- Files: `src/main/network-guard.ts`
- Risk: Malicious URLs may bypass whitelist due to URL parsing edge cases
- Improvement: Add comprehensive URL parsing test suite with edge cases
- Priority: Medium — affects security

**PresetModule module configuration:**
- What's not tested: Empty modules array, null values, additional unknown properties in preset JSON
- Files: Tests exist but limited to happy path (preset-config.test.ts)
- Risk: Malformed preset data could cause downstream errors in UI/Backend
- Improvement: Add negative test cases; validate schema robustly
- Priority: Low — schema validation works but coverage is incomplete

**Docker cleanup with custom container names:**
- What's not tested: Projects with renamed services, multi-project setups
- Files: `src/main/docker.ts:656-694` (cleanupStaleContainers)
- Risk: Cleanup may remove wrong containers if user has custom project structure
- Improvement: Parameterize service names; add tests for various docker-compose.yml structures
- Priority: Medium — affects uninstall reliability

**E2E Electron app tests with Playwright:**
- What's not tested: CrossTrade dApp container launch (structure test only, no deployment)
- Files: `tests/e2e/electron-crosstrade-defi.live.spec.ts`
- Risk: Electron app may fail to launch dApp even if Platform UI test passes
- Status: Being implemented in Phase 05 (e2e-sepolia-validation)
- Priority: High — final validation gate

## Incomplete Features

**Admin credential persistence across app restart:**
- Problem: Admin credentials passed at container start time not saved; app must prompt again on restart
- Files: `src/main/webview.ts:55-57` (setAdminCredentials stores in memory only)
- Blocks: Auto-login on app restart; credential recovery
- Recommendation: Keystore support for admin credentials (encrypted storage like seedphrase)

**AWS profile caching:**
- Problem: Credentials cached in memory but no persistent session storage
- Files: `src/main/aws-auth.ts:50`
- Blocks: AWS credential reuse across app restarts
- Recommendation: Store access tokens in safe storage similar to keystore

**CrossTrade dApp health check integration:**
- Problem: No IPC handler to check if dApp container is running/healthy
- Files: Platform launcher exists but no status endpoint
- Blocks: UI cannot display dApp status; user doesn't know if dApp failed to start
- Recommendation: Add `docker:check-crosstrade-health` IPC handler
- Status: Pending Phase 05 integration with Backend

**Error message context (code + details):**
- Problem: Error messages are strings; no structured error codes for programmatic handling
- Files: Throughout `src/main/`
- Blocks: Renderer cannot distinguish between port conflicts vs network issues vs disk space
- Recommendation: Create ErrorCode enum; return { code, message, details } from IPC handlers

## Known Limitations

**Electron DevTools open by default in development:**
- Limitation: Development builds include `webPreferences.devTools = true`
- Impact: Credentials visible in DevTools; intentional for debugging but risky if shared
- Mitigation: Only in development mode; production builds disable DevTools

**No remote server capability (hardcoded localhost):**
- Limitation: Cannot point to deployed backend instance
- Impact: Desktop app only works with local Docker Compose setup
- Status: Known limitation; remote support planned for future release

**Single-window only (no multi-window support):**
- Limitation: App enforces single instance lock
- Impact: User cannot open app twice (intentional) or open multiple windows (limitation)
- Status: Acceptable for single-user desktop app

**Import path aliases not available in test files:**
- Limitation: Tests use relative paths while source uses explicit imports
- Impact: Refactoring source paths requires updating all test imports
- Status: Acceptable but improves with vitest.config alias setup

---

*Concerns audit: 2026-04-09*
