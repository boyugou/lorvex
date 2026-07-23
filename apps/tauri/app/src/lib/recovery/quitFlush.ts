import { listen } from '@tauri-apps/api/event';

import { createAsyncTauriListenerScope, type AsyncTauriListenerScope } from '../tauriListenerLifecycle';

/**
 * Coordinated shutdown hooks for flushing pending debounced writes on
 * app Quit.
 *
 * Any controller can register an async flush callback here; on the
 * Rust-side `lorvex-quit-flush` event (emitted ~1 s before
 * `app_handle.exit(0)`), every registered flush fires in parallel
 * and the Rust side sleeps just long enough to let them complete
 * before tearing down. Without this, ⌘Q would tear down the process
 * before fire-and-forget unmount-time `void updateX(...)` IPC calls
 * could complete, silently discarding the last debounce window of
   * focus-mode elapsed time.
 *
 * Register inside a `useEffect`; unregister in the cleanup. Do not
 * call `updateX` directly from a flush that shares the writer with
 * the already-inflight debounce — clear the pending timer first and
 * write the freshest draft.
 */
type QuitFlush = () => Promise<void>;
type QuitFlushDeps = {
  listen: typeof listen;
};

const registered = new Set<QuitFlush>();
const runtimeDeps: QuitFlushDeps = { listen };
let deps: QuitFlushDeps = runtimeDeps;

/**
 * Register a flush callback to run when the app is about to exit.
 * Returns an unregister function suitable for a `useEffect` cleanup.
 */
export function registerQuitFlush(flush: QuitFlush): () => void {
  registered.add(flush);
  return () => {
    registered.delete(flush);
  };
}

let installed = false;
let listenerScope: AsyncTauriListenerScope | null = null;
let installGeneration = 0;

/**
 * Install the global `lorvex-quit-flush` listener. Idempotent; safe
 * to call multiple times (e.g. on React strict-mode double-mount).
 * Call once from a top-level component like `App.tsx`.
 */
export function installQuitFlushListener(): () => void {
  if (installed) {
    return () => {};
  }
  installed = true;
  const generation = ++installGeneration;
  const scope = createAsyncTauriListenerScope();
  listenerScope = scope;

  scope.add(
    deps.listen('lorvex-quit-flush', () => {
      // Tauri's `listen` callback slot is `() => void`; we discard the
      // promise explicitly. `allSettled` still keeps one failing flush
      // from starving the others — a failed IPC write shouldn't
      // block the remaining flushes from running.
      void (async () => {
        const flushers = Array.from(registered);
        await Promise.allSettled(flushers.map((flush) => flush()));
      })();
    }),
    () => {
      // Non-Tauri environments (e.g. test runner) have no event bus.
      // The registry still works for in-process calls, just no wake-up.
      if (generation === installGeneration) {
        installed = false;
      }
    },
  );

  return () => {
    if (generation === installGeneration) {
      installGeneration += 1;
    }
    if (listenerScope === scope) {
      listenerScope = null;
    }
    scope.dispose();
    installed = false;
  };
}

export const __TEST_ONLY__ = {
  setDepsForTests(overrides: Partial<QuitFlushDeps>): void {
    deps = { ...runtimeDeps, ...overrides };
  },
  resetDepsForTests(): void {
    deps = runtimeDeps;
    registered.clear();
    installed = false;
    listenerScope?.dispose();
    listenerScope = null;
    installGeneration = 0;
  },
};
