export type BackgroundMaintenanceTimerHandle = ReturnType<typeof globalThis.setTimeout>;

export interface BackgroundMaintenanceTimerHost {
  clearTimeout: (handle: BackgroundMaintenanceTimerHandle) => void;
  setTimeout: (
    callback: () => void,
    delayMs: number,
  ) => BackgroundMaintenanceTimerHandle;
}

export function createBrowserBackgroundMaintenanceTimerHost(): BackgroundMaintenanceTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

interface InstallBackgroundMaintenanceLoopOptions {
  delayMs: number;
  run: () => Promise<void>;
  /**
   * Called with any error thrown by `run`. The loop primitive owns the
   * catch+report contract end-to-end so call sites do not have to wrap
   * their tick body in their own try/catch — `.catch(() =>
   * undefined)` here silently swallowed everything that escaped a
   * caller's inner try/catch (or any error from `reportClientError`
   * itself), making real failures invisible in production. Wire this
   * to your structured logger (e.g. `reportClientError`) at the
   * caller's hook layer.
   *
   * The loop continues to reschedule on the next tick regardless of
   * what `onError` does — a thrown error from `onError` itself is
   * suppressed (we never want a logger fault to break the maintenance
   * cadence).
   */
  onError: (error: unknown) => void;
  timerHost: BackgroundMaintenanceTimerHost;
}

export function installBackgroundMaintenanceLoop(
  options: InstallBackgroundMaintenanceLoopOptions,
): () => void {
  let cancelled = false;
  let timer: BackgroundMaintenanceTimerHandle | null = null;

  const tick = () => {
    void options.run()
      .catch((error: unknown) => {
        try {
          options.onError(error);
        } catch {
          // A faulty logger must not break the maintenance loop.
          // Errors from `onError` are intentionally suppressed here —
          // the logger is the surface that should detect its own
          // outages, not this primitive.
        }
      })
      .finally(() => {
        if (cancelled) {
          return;
        }
        timer = options.timerHost.setTimeout(() => {
          tick();
        }, options.delayMs);
      });
  };

  tick();

  return () => {
    cancelled = true;
    if (timer === null) {
      return;
    }
    options.timerHost.clearTimeout(timer);
    timer = null;
  };
}
