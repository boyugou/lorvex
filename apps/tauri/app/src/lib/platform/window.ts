// Platform wrapper for the Tauri window API.
//
// Component code MUST import `getCurrentWindow` and related primitives
// through this module rather than reaching `@tauri-apps/api/window`
// directly so the platform-coupling surface stays scoped to a single
// file. The `no-restricted-imports` ESLint rule (see
// `app/eslint.config.js`) enforces this boundary inside
// `src/components/**`; the wrapper itself is the one allowed consumer.
//

export {
  getCurrentWindow,
} from '@tauri-apps/api/window';
