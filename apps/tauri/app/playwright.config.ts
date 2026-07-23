import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for Lorvex E2E / visual regression tests.
 *
 * Prerequisites:
 *   1. Install browsers: npx -w app playwright install chromium
 *   2. Run tests:        npx -w app playwright test
 *
 * The webServer block below starts the Vite dev server automatically on
 * port 1420. No Tauri backend is required — the tests mock Tauri IPC via
 * addInitScript (see individual spec files).
 *
 * In CI the dev server is always started fresh. Locally, an already-running
 * server on port 1420 is reused to avoid startup delay.
 */
export default defineConfig({
  testDir: './e2e',
  outputDir: './e2e/test-results',
  snapshotDir: './e2e/snapshots',
  timeout: 30_000,
  expect: {
    toHaveScreenshot: {
      // Platform baselines are committed separately; keep the global drift
      // budget small so shifted controls/text blocks fail loudly.
      maxDiffPixels: 250,
    },
  },
  use: {
    baseURL: 'http://localhost:1420',
    // Consistent viewport for screenshot comparison.
    viewport: { width: 1280, height: 800 },
    // Disable animations for deterministic screenshots.
    actionTimeout: 10_000,
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  /* Start the Vite dev server before running tests. */
  webServer: {
    command: 'npx vite --port 1420',
    url: 'http://localhost:1420',
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
