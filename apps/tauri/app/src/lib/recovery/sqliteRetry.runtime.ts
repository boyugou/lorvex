type SqliteRetryTimerHandle = ReturnType<typeof globalThis.setTimeout>;

export interface SqliteRetryTimerHost {
  setTimeout: (
    callback: () => void,
    delayMs: number,
  ) => SqliteRetryTimerHandle;
}

export function createBrowserSqliteRetryTimerHost(): SqliteRetryTimerHost {
  return {
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function waitForBusyRetryDelay(
  delayMs: number,
  timerHost: SqliteRetryTimerHost,
  signal?: AbortSignal,
): Promise<void> {
  if (signal?.aborted) {
    return Promise.reject(signal.reason ?? new DOMException('Aborted', 'AbortError'));
  }
  if (delayMs <= 0) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    const handle = timerHost.setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, delayMs);
    const onAbort = () => {
      // We can't `clearTimeout` (the host doesn't expose it on the
      // interface), but we can short-circuit by rejecting and letting
      // the resolved-callback no-op since the awaiter is already gone.
      // The pending timer fires once and dies — no leak across mounts.
      signal?.removeEventListener('abort', onAbort);
      reject(signal?.reason ?? new DOMException('Aborted', 'AbortError'));
      void handle; // keep handle reachable for GC tracking; clearTimeout omitted by design
    };
    if (signal) {
      signal.addEventListener('abort', onAbort, { once: true });
    }
  });
}
