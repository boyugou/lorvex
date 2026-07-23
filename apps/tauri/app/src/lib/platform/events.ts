// Platform wrapper for the Tauri event bus.
//
// Component code MUST import `listen` / `emit` through this module
// rather than reaching `@tauri-apps/api/event` directly so the
// platform-coupling surface stays scoped to a single file. The
// `no-restricted-imports` ESLint rule (see `app/eslint.config.js`)
// enforces this boundary inside `src/components/**`; the wrapper
// itself is the one allowed consumer.
//

export { listen, emit } from '@tauri-apps/api/event';
