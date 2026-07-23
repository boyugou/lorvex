export interface ToastTimerHost {
  setTimeout: (callback: () => void, delayMs: number) => unknown;
  /**
   * Cancel a previously-scheduled timer. Implementations that don't
   * support cancellation (e.g. the no-op host used in tests) may
   * leave this as a no-op; callers must remain correct under both
   * "cancel works" and "cancel is a no-op" — i.e. the scheduled
   * callback must itself be idempotent and tolerant of running after
   * its work is already done.
   */
  clearTimeout: (handle: unknown) => void;
}

export function createBrowserToastTimerHost(): ToastTimerHost {
  return {
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
    clearTimeout: (handle) => {
      if (typeof handle === 'number') {
        globalThis.clearTimeout(handle);
      }
    },
  };
}

/**
 * Schedule a toast timer and return a cancel function. Calling the
 * returned cancel is idempotent: re-cancelling does nothing, and the
 * scheduled callback never fires after a successful cancel — letting
 * callers (e.g. `dismissToast` → `removeToast` flow) avoid the
 * spurious second `removeToast(id)` invocation when the CSS
 * `transitionend` arrives before the safety fallback.
 */
export function scheduleToastTimer(
  host: ToastTimerHost,
  callback: () => void,
  delayMs: number,
): () => void {
  const handle = host.setTimeout(callback, delayMs);
  let cancelled = false;
  return () => {
    if (cancelled) return;
    cancelled = true;
    host.clearTimeout(handle);
  };
}
