import path from 'node:path';
import { defineConfig } from 'vitest/config';

// Vitest harness for the `app/` workspace. This is intentionally separate from
// `vite.config.ts` so the unit-test runner stays minimal and free of the React
// / Tailwind / bundle-analyzer plumbing that powers the Tauri build. Tests
// target the `.logic.ts` purified-function tier — zero IO, zero Tauri or
// React imports — so a Node environment is sufficient. See issue #2940-M3.
export default defineConfig({
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@lorvex/shared/types': new URL('../shared/src/types.ts', import.meta.url).pathname,
      '@lorvex/shared/validation': new URL('../shared/src/validation.ts', import.meta.url).pathname,
    },
    dedupe: ['react', 'react-dom'],
  },
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
    // #4415: shared Tauri shim. Mocks `@tauri-apps/api/core` (so
    // individual tests don't have to wire `vi.mock` per file) and
    // stubs `window.__TAURI_INTERNALS__` so any IPC wrapper imported
    // transitively does not fault during module init under either
    // Node or jsdom. Per-test overrides via `vi.mocked(...)` still
    // work — the shim only provides a safe default.
    setupFiles: ['./vitest.setup.ts'],
    // Browser/DOM tests are explicitly out of scope for this harness wave; they
    // need jsdom and live alongside React components. Adding them later only
    // requires flipping `environment` per-file via the vitest `// @vitest-environment`
    // pragma, no global config change.
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
      include: ['src/**/*.logic.ts'],
      exclude: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
    },
  },
});
