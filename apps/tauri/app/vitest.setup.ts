/**
 * Vitest harness setup — shared Tauri shim.
 *
 * #4415: unit tests under the vitest harness execute in a non-browser
 * environment (Node or jsdom), neither of which provides the runtime
 * surface that `@tauri-apps/api` expects. Tests that transitively
 * import an IPC wrapper (`@/lib/ipc/...`) load `@tauri-apps/api/core`,
 * whose initialiser dereferences `window.__TAURI_INTERNALS__` at
 * import time. Under jsdom that throws `window is not defined` during
 * module resolution (the property access happens before the test body
 * ever runs); under Node the throw shape is similar.
 *
 * This setup file unifies the two symmetric mitigations every previous
 * test had to wire up by hand:
 *
 *   1. `vi.mock('@tauri-apps/api/core', ...)` returns a stub `invoke`
 *      that resolves with `undefined`. Tests that exercise specific
 *      IPC paths override this with `vi.mocked(...).mockResolvedValue`
 *      inside their own `beforeEach` — the global mock is the safe
 *      default, not a contract.
 *   2. `window.__TAURI_INTERNALS__` is populated with a minimal
 *      object so any sibling `@tauri-apps/api/*` import that reaches
 *      past the mocked `core` (e.g. `event`, `webviewWindow`) sees a
 *      well-formed runtime descriptor instead of `undefined`.
 *
 * Both shims are inert under the `environment: 'node'` baseline that
 * the existing tests rely on — the `vi.mock` registers regardless of
 * environment, and the `globalThis.window` assignment is a no-op when
 * `window` already resolves to the jsdom global.
 */
import { vi } from 'vitest';

vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn(async () => undefined),
  convertFileSrc: (path: string) => path,
}));

vi.mock('@tauri-apps/api/event', () => ({
  emit: vi.fn(async () => undefined),
  listen: vi.fn(async () => () => undefined),
  once: vi.fn(async () => () => undefined),
}));

vi.mock('@tauri-apps/api/webviewWindow', () => ({
  getCurrentWebviewWindow: () => ({
    listen: vi.fn(async () => () => undefined),
    emit: vi.fn(async () => undefined),
    label: 'test',
  }),
}));

const globalAny = globalThis as unknown as {
  window?: Record<string, unknown>;
  __TAURI_INTERNALS__?: Record<string, unknown>;
};
const tauriInternalsStub = {
  invoke: async () => undefined,
  transformCallback: () => 0,
  metadata: { currentWindow: { label: 'test' }, currentWebview: { label: 'test' } },
};
if (typeof globalAny.window !== 'undefined') {
  globalAny.window.__TAURI_INTERNALS__ = tauriInternalsStub;
}
globalAny.__TAURI_INTERNALS__ = tauriInternalsStub;
