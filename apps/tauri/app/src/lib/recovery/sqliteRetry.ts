import { toIpcErrorMessage } from '../ipc/core';
import {
  computeJitteredBusyRetryDelay,
  isRetryableSqliteBusyMessage,
  SQLITE_BUSY_RETRY_BASE_DELAYS_MS,
} from './sqliteRetry.logic';
import {
  createBrowserSqliteRetryTimerHost,
  waitForBusyRetryDelay,
} from './sqliteRetry.runtime';

const sqliteRetryTimerHost = createBrowserSqliteRetryTimerHost();

/**
 * Check whether an IPC error indicates a transient SQLite BUSY/locked condition
 * that is safe to retry after a short delay.
 *
 * Classification is substring-based because Tauri collapses the Rust
 * `rusqlite::Error` into its Display string when it crosses the IPC
 * boundary; the structured code is not preserved. All three phrases
 * below are produced by upstream SQLite and are locale-independent
 * (SQLite emits English-only error text regardless of host locale,
 * see sqlite3.c:errstr). A future SQLite major version that rewords
 * these would be caught by the existing ``-style live-wording
 * pins — see the Rust-side companion for the counterpart
 * change.
 */
function isRetryableSqliteBusyError(error: unknown): boolean {
  const msg = typeof error === 'string' ? error : toIpcErrorMessage(error);
  return isRetryableSqliteBusyMessage(msg);
}

/**
 * Retry an async operation with exponential backoff + per-attempt
 * jitter when the operation fails with a transient SQLite BUSY
 * error. Non-retryable errors are re-thrown immediately.
 *
   * An optional AbortSignal short-circuits both the inter-attempt wait
   * and the next attempt so a cancelled write does not land after the
   * originating surface closes.
 */
export async function withBusyRetry<T>(
  operation: () => Promise<T>,
  options: { signal?: AbortSignal | undefined } = {},
): Promise<T> {
  const { signal } = options;
  let lastError: unknown = null;
  for (const baseDelayMs of SQLITE_BUSY_RETRY_BASE_DELAYS_MS) {
    if (signal?.aborted) {
      throw signal.reason ?? new DOMException('Aborted', 'AbortError');
    }
    const delayMs = computeJitteredBusyRetryDelay(baseDelayMs, Math.random());
    await waitForBusyRetryDelay(delayMs, sqliteRetryTimerHost, signal);
    if (signal?.aborted) {
      throw signal.reason ?? new DOMException('Aborted', 'AbortError');
    }
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (!isRetryableSqliteBusyError(error)) {
        throw error;
      }
    }
  }
  throw lastError ?? new Error('SQLite busy retry exhausted');
}
