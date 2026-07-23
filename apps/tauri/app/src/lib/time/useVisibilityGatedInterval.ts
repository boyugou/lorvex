import { useEffect, useRef } from 'react';
import {
  createBrowserVisibilityGatedIntervalRuntimeDeps,
  startVisibilityGatedIntervalRuntime,
} from './intervalHooks.runtime';

/**
 * Run `cb` every `intervalMs` while the document is visible.
 *
 * On mount (or whenever the tab becomes visible), the interval is
 * (re)armed and `cb` is invoked once immediately so the UI "catches
 * up" after a hidden period. While the document is hidden the timer
 * is fully cleared — no wake-ups, no state updates, no IPC.
 *
 * the naïve `setInterval` pattern kept
 * calendar pollers, notification checks, sync-status refresh, and
 * retention-cleanup ticking on every user's machine even while their
 * window was hidden in the Dock or collapsed in the menu-bar. macOS
 * surfaces these wake-ups in Activity Monitor's Energy Impact column
 * and they prevent the system from going into the deepest sleep
 * state. This hook collapses the pattern to one place.
 *
 * Callers must treat `cb` as idempotent — on resume we always fire
 * once immediately, and the resume delta is not passed to the
 * callback. That's fine for "refresh data" style work (TanStack
 * invalidation, polling a backend for state) but not for elapsed-
 * time accumulation. For wall-clock timers, use a wall-clock anchor
 * pattern.
 *
 * `cb` should be stable (memoized) — the hook re-arms on every
 * identity change.
 */
export function useVisibilityGatedInterval(cb: () => void, intervalMs: number): void {
  const cbRef = useRef(cb);
  cbRef.current = cb;

  useEffect(() => {
    return startVisibilityGatedIntervalRuntime({
      intervalMs,
      ...createBrowserVisibilityGatedIntervalRuntimeDeps(() => cbRef.current()),
    });
  }, [intervalMs]);
}
