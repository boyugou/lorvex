export interface TaskCardCompletionRefreshTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

/**
 * minimal cancellation token surface used by the
 * task-card completion-refresh scheduler. We don't reach for a real
 * `AbortController` because the consumer never needs the AbortSignal —
 * just the boolean state and a `cancel()` trigger. A lightweight
 * struct keeps the runtime testable without polyfilling AbortController
 * in the node-only test environment.
 *
 * Lifecycle:
 *   1. `createTaskCardCompletionRefreshAbortToken()` returns a fresh
 *      token in the un-aborted state.
 *   2. `scheduleTaskCardCompletionRefresh` checks the token before
 *      firing the deferred `refresh`. If the token is aborted by then
 *      the refresh is skipped.
 *   3. The undo path (or unmount) calls `token.abort()` to short-circuit
 *      any pending refresh that hasn't fired yet.
 */
export interface TaskCardCompletionRefreshAbortToken {
  abort: () => void;
  readonly aborted: boolean;
}

interface TaskCardCompletionRefreshScheduleDeps {
  delayMs: number;
  refresh: () => void;
  timerHost: TaskCardCompletionRefreshTimerHost;
  /**
   * Optional abort token. When provided, the deferred `refresh` is
   * skipped if the token is aborted at the moment the timer fires.
   * Callers should also `clearTimeout()` proactively for the common
   * case; the abort check is the safety net for in-flight callbacks.
   */
  abortToken?: TaskCardCompletionRefreshAbortToken;
}

export function createTaskCardCompletionRefreshAbortToken(): TaskCardCompletionRefreshAbortToken {
  let aborted = false;
  return {
    abort: () => { aborted = true; },
    get aborted() { return aborted; },
  };
}

export function createBrowserTaskCardCompletionRefreshTimerHost(): TaskCardCompletionRefreshTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function scheduleTaskCardCompletionRefresh({
  delayMs,
  refresh,
  timerHost,
  abortToken,
}: TaskCardCompletionRefreshScheduleDeps): unknown {
  return timerHost.setTimeout(() => {
    if (abortToken?.aborted) return;
    refresh();
  }, delayMs);
}

export function clearTaskCardCompletionRefresh(
  timerHost: Pick<TaskCardCompletionRefreshTimerHost, 'clearTimeout'>,
  handle: unknown,
): void {
  timerHost.clearTimeout(handle);
}
