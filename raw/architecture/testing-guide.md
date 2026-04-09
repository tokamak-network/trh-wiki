# Testing Patterns

**Analysis Date:** 2026-04-09

## Test Framework

**Runner:**
- Vitest 4.1.0 - Unit and integration test runner
- Config: `vitest.config.mts`
- Default environment: `happy-dom` (lightweight DOM for React tests)
- Node environment: explicit `// @vitest-environment node` at top of file for backend tests

**Assertion Library:**
- Vitest built-in (`import { describe, it, expect } from 'vitest'`)
- Testing Library (React testing): `@testing-library/react`, `@testing-library/user-event`
- Playwright for E2E tests: `@playwright/test`

**Run Commands:**
```bash
npm test                    # Run all unit/integration tests (Vitest)
npm run test:watch         # Watch mode (re-run on file change)
npm run test:e2e           # Run E2E tests (Playwright)
npm run test:matrix        # Run matrix of preset deployments (bash script)
npm run test:matrix:full   # Full cycle with funding, deployment, and verification
```

## Test File Organization

**Location:**
- Unit/integration tests: co-located with source or in `tests/unit/` directory
  - `src/renderer/pages/SetupPage.test.tsx` — React component tests
  - `src/main/aws-auth.test.ts` — Electron main process tests
  - `tests/unit/*.test.ts` — Validation and integration tests (presets, Docker, IPC)
- E2E tests: `tests/e2e/*.spec.ts` and `tests/e2e/electron-*.live.spec.ts`
- Test helpers: `tests/helpers/*.ts` (load-fixtures, load-compose, auth)
- Test schemas: `tests/schemas/*.schema.ts` (Zod validation schemas)

**Naming:**
- Unit/integration: `*.test.ts` or `*.test.tsx` suffix
- E2E: `*.spec.ts` suffix
- Electron E2E: `electron-*.live.spec.ts` for live tests with real services

**Directory Structure:**
```
tests/
├── unit/                     # Unit and integration tests
│   ├── preset-config.test.ts
│   ├── docker-stack.test.ts
│   ├── ipc-channels.test.ts
│   ├── deploy-local.test.ts
│   └── ...
├── e2e/                      # E2E tests (Playwright)
│   ├── preset-wizard.spec.ts
│   ├── screenshots.spec.ts
│   ├── bridge-explorer.live.spec.ts
│   ├── electron-*.live.spec.ts
│   └── helpers/
│       └── auth.ts           # Authentication helpers
├── helpers/                  # Shared test utilities
│   ├── load-fixtures.ts      # Load preset fixtures from JSON
│   └── load-compose.ts       # Parse docker-compose.yml
├── schemas/                  # Zod validation schemas
│   ├── preset.schema.ts
│   ├── docker-compose.schema.ts
│   └── ...
└── fixtures/                 # Test data
    └── presets.json          # Synced from backend via `npm run sync-fixtures`
```

## Test Structure

**Suite Organization:**
```typescript
// Example from SetupPage.test.tsx
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, cleanup } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

describe('SetupPage - Step 6 Key Setup', () => {
  const onComplete = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    onComplete.mockReset();
  });

  afterEach(() => {
    cleanup();
  });

  it('shows key setup form after all steps complete', async () => {
    // Test implementation
  });
});
```

**Patterns:**

- **Setup:** `beforeEach()` clears mocks and resets state. File-level hoisting with `vi.hoisted()` runs before imports (ensures `window.electronAPI` exists when component loads)
  
  ```typescript
  const { mockElectronAPI, mockKeystore } = vi.hoisted(() => {
    // Mock objects created here, runs before imports
  });
  (globalThis as any).electronAPI = mockElectronAPI;
  ```

- **Teardown:** `afterEach()` calls `cleanup()` to remove DOM nodes. Temporary directories cleaned in `afterEach()` for file I/O tests.

- **Assertion pattern:** Both BDD (`expect().toBeX()`) and error-based (`expect(() => fn()).toThrow()`)
  
  ```typescript
  expect(mockFn).toHaveBeenCalledWith(expectedValue);
  expect(screen.getByText('text')).toBeInTheDocument();
  expect(() => awsAuth.loadProfile('nonexistent')).toThrow();
  ```

- **Async testing:** `waitFor()` with timeout for async operations
  
  ```typescript
  await waitFor(() => {
    expect(screen.getByText(/text/i)).toBeInTheDocument();
  }, { timeout: 10000 });
  ```

## Mocking

**Framework:** `vi` (Vitest) for mocks and spies

**Patterns:**

```typescript
// Mock an external module
vi.mock('electron', () => ({
  shell: {
    openExternal: vi.fn(() => Promise.resolve()),
  },
}));

// Mock with manual implementation
vi.mock('@aws-sdk/client-sso-oidc', () => ({
  SSOOIDCClient: vi.fn().mockImplementation(() => ({
    send: vi.fn(),
  })),
  RegisterClientCommand: vi.fn(),
}));

// Mock CSS and asset imports
vi.mock('./SetupPage.css', () => ({}));
vi.mock('../assets/logo/logo.svg', () => ({ default: 'logo.svg' }));

// Mock return values
mockKeystore.validate.mockImplementation(async (m: string) => {
  const words = m.trim().split(/\s+/);
  return words.length === 12 || words.length === 24;
});

// Mock rejection for error testing
mockKeystore.store.mockRejectedValueOnce(new Error('Encryption failed'));
```

**What to Mock:**
- External APIs (AWS SDK, Electron, OS calls)
- CSS and asset imports (prevent build errors in test environment)
- Browser APIs when testing React components (fetch, localStorage via `vi.mock()` or direct `vi.spyOn()`)
- Child processes and file system operations (use `vi.mock('child_process')` or `vi.mock('fs')`)

**What NOT to Mock:**
- Core business logic (test real behavior)
- Validation schemas (Zod), use real instances
- Type definitions
- Internal module dependencies (let them be required naturally)

## Fixtures and Factories

**Test Data:**
```typescript
// From SetupPage.test.tsx
const VALID_MNEMONIC = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

const MOCK_ADDRESSES = {
  admin: '0x9858EfFD232B4033E47d90003D41EC34EcaEdA94',
  proposer: '0x6a3B248855C2D2c4a0F3bA8A1ad62fB188f0B8DB',
  batcher: '0xdEADBEeF00000000000000000000000000000003',
  challenger: '0xdEADBEeF00000000000000000000000000000004',
  sequencer: '0xdEADBEeF00000000000000000000000000000005',
};

// Helper function for reusable test setup
async function renderAndWaitForKeySetup() {
  render(<SetupPage adminEmail="admin@test.com" adminPassword="password" onComplete={onComplete} />);
  await waitFor(() => {
    expect(screen.getByText(/Enter your seed phrase/i)).toBeInTheDocument();
  }, { timeout: 10000 });
}
```

**Location:**
- Test data constants defined at top of test file
- Helper functions defined in same file when used by multiple test cases (e.g., `fillSeedPhrase()`, `completeStep1And2()`)
- Shared fixtures loaded from `tests/fixtures/` via helper functions in `tests/helpers/` (e.g., `loadPresets()`, `loadCompose()`)
- Fixture JSON files synced from backend via `npm run sync-fixtures` command

**Syncing Fixtures:**
```bash
npm run sync-fixtures          # Update tests/fixtures/presets.json from backend
npm run sync-fixtures:dry     # Dry-run (show what would change)
```

## Coverage

**Requirements:**
- No minimum coverage enforced
- Coverage not tracked by default
- Test focus is on critical paths: preset definitions, Docker operations, IPC contracts, and E2E user flows

**View Coverage:**
```bash
# Not configured, but can add with:
vitest run --coverage
```

## Test Types

**Unit Tests:**
- Scope: Individual functions, components, modules
- Approach: Isolated mocks for external dependencies
- Examples:
  - `aws-auth.test.ts` — Tests AWS credential loading, profile parsing, token management
  - `SetupPage.test.tsx` — Tests React component rendering, user interactions, state transitions
  - `preset-config.test.ts` — Tests preset schema validation and parameter values

**Integration Tests:**
- Scope: Contract between modules (IPC channels, fixture loading)
- Approach: Real modules, mocked external services
- Examples:
  - `ipc-channels.test.ts` — Validates IPC handler/invoke channel pairs match (no orphans)
  - `docker-stack.test.ts` — Validates docker-compose.yml structure (services, dependencies, healthchecks)
  - `deploy-local.test.ts` — Tests local deployment flow steps
  - `funding-flow.test.ts` — Tests funding transaction sequencing

**E2E Tests:**
- Framework: Playwright
- Scope: Full user workflows (preset selection → configuration → deployment)
- Config files:
  - `playwright.config.ts` — Browser-based tests against Platform UI (port 3009 with MSW mocks)
  - `playwright.electron.config.ts` — Electron app tests against real backend (requires Docker running)
  - `playwright.live.config.ts` — Live backend tests (requires port 3000 accessible)
- Run modes:
  - MSW mode (mocked): `npm run test:e2e` — Tests UI logic without backend
  - Live mode: Electron app running with real backend services
  - Matrix mode: `npm run test:matrix` — Tests all 4 presets end-to-end

## Common Patterns

**Async Testing:**
```typescript
// Wait for async operation to complete
const user = userEvent.setup();
await user.type(textarea, VALID_MNEMONIC);

await waitFor(() => {
  expect(screen.getByText('Derived Addresses')).toBeInTheDocument();
});

// Or with Playwright
await expect(page.getByText('text')).toBeVisible({ timeout: 15000 });
```

**Error Testing:**
```typescript
// Playwright
await expect(() => awsAuth.loadProfile('nonexistent')).toThrow();

// React Testing Library + userEvent
const user = userEvent.setup();
await user.type(textarea, 'invalid seed');
await waitFor(() => {
  expect(screen.getByText(/Invalid seed phrase/i)).toBeInTheDocument();
});

// Rejection testing
mockKeystore.store.mockRejectedValueOnce(new Error('Encryption failed'));
await user.click(screen.getByText('Save & Continue'));
await waitFor(() => {
  expect(screen.getByText('Keystore Error')).toBeInTheDocument();
});
```

**Helper Functions in Playwright:**
```typescript
// Example from preset-wizard.spec.ts
async function fillSeedPhrase(page: Page): Promise<void> {
  const seedInputs = page.locator('input[placeholder="•••••"]');
  await expect(seedInputs.first()).toBeVisible();
  await seedInputs.first().fill(TEST_MNEMONIC_WORDS.join(' '));
  await page.locator('#seedPhraseConfirm').click();
}

async function completeStep1And2(page: Page, presetName: string, presetId: string): Promise<void> {
  await page.goto('/rollup/create');
  await expect(page.getByText('Choose a Deployment Preset')).toBeVisible({ timeout: 15000 });
  // ... more steps
}
```

**Parametric Tests:**
```typescript
// Vitest
it.each(['general', 'defi', 'gaming', 'full'] as const)(
  '%s passes Zod schema validation',
  (presetId) => {
    expect(() => PresetDefinitionSchema.parse(presets[presetId])).not.toThrow();
  },
);

// Playwright
const PRESETS = [
  { id: 'general', name: 'General Purpose', batchFreq: '1800' },
  { id: 'defi', name: 'DeFi', batchFreq: '900' },
] as const;

for (const preset of PRESETS) {
  test(`preset ${preset.id} shows batch frequency ${preset.batchFreq}`, async ({ page }) => {
    // Test implementation
  });
}
```

## Test Configuration Details

**Vitest Config (`vitest.config.mts`):**
```typescript
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '../trh-platform-ui/src'),
    },
  },
  test: {
    globals: true,                              // Use describe/it/expect without imports
    environment: 'happy-dom',                    // Default: lightweight DOM for React
    setupFiles: ['./src/test/setup.ts'],         // Setup: imports testing-library/jest-dom
    include: ['src/**/*.test.{ts,tsx}', 'tests/**/*.test.{ts,tsx}'],
    css: { modules: { classNameStrategy: 'non-scoped' } },
  },
});
```

**Playwright Config (`playwright.config.ts`):**
```typescript
export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:3009',
    trace: 'on-first-retry',
  },
  webServer: {
    command: 'NEXT_PUBLIC_MSW=true npm run dev -- -p 3009',
    url: 'http://localhost:3009',
    cwd: '../trh-platform-ui',
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
});
```

**Electron E2E Config (`playwright.electron.config.ts`):**
```typescript
export default defineConfig({
  testDir: './tests/e2e',
  testMatch: '**/electron-*.live.spec.ts',
  fullyParallel: false,          // Serial — Electron is a singleton
  forbidOnly: !!process.env.CI,
  retries: 0,                    // No retries — each runs deploys real contracts
  workers: 1,
  timeout: 1_800_000,            // 30 min per test
  expect: { timeout: 120_000 },  // 2 min page load
  reporter: [['html', { outputFolder: 'playwright-report-electron' }]],
  projects: [{ name: 'electron' }],
});
```

## Pre-flight Checks

**Validate Before Committing:**
```bash
npm run preflight    # Runs: sync-fixtures:dry, test, test:e2e
```

This ensures:
1. Fixtures are in sync (no backend changes missed)
2. All unit/integration tests pass
3. All E2E tests pass (MSW mode)

## Special Test Modes

**MSW Mode (Mocked Service Worker):**
- Used in `preset-wizard.spec.ts` and other E2E tests
- Enabled by `NEXT_PUBLIC_MSW=true` environment variable
- Mocks API responses without real backend
- Port: 3009 (different from production 3000)

**Live Mode:**
- Tests against real backend services (Docker running)
- Tests in `bridge-explorer.live.spec.ts` and `electron-*.live.spec.ts`
- Requires:
  - `make up` (Docker services running)
  - Backend API accessible at `http://localhost:8000`
  - Platform UI at `http://localhost:3000` or Electron app

**Matrix Mode:**
- Bash script: `tests/e2e/matrix/run-matrix.sh`
- Tests all 4 presets sequentially
- Options:
  - `--full-cycle`: Includes funding, deployment, and verification for each preset
  - Default: Quick validation only

---

*Testing analysis: 2026-04-09*
