import { toIpcErrorMessage } from '../ipc/core';
import { isTauriRuntimeAvailable } from '../platform/tauriRuntime';

const CLIENT_ERROR_LOG_DEDUPE_MS = 5_000;
const recentClientErrorAt = new Map<string, number>();
const inflightClientErrorLogs = new Set<string>();
const queuedClientErrorLogs = new Map<string, { count: number; latestQueuedAt: number }>();
type ClientErrorLogLevel = 'debug' | 'info' | 'warn' | 'error';
type AppendErrorLogFn = (
  source: string,
  message: string,
  details?: string,
  level?: ClientErrorLogLevel,
  signal?: AbortSignal,
) => Promise<void>;
let appendErrorLogImpl: AppendErrorLogFn | null = null;

async function appendErrorLogDefault(...args: Parameters<AppendErrorLogFn>): Promise<void> {
  const { appendErrorLog } = await import('../ipc/settings');
  await appendErrorLog(...args);
}

function pruneRecentClientErrorFingerprints(now: number): void {
  if (recentClientErrorAt.size > 200) {
    for (const [fingerprint, ts] of recentClientErrorAt.entries()) {
      if (now - ts > CLIENT_ERROR_LOG_DEDUPE_MS * 4) {
        recentClientErrorAt.delete(fingerprint);
      }
    }
  }
}

function shouldSkipClientErrorLog(key: string, now: number = Date.now()): boolean {
  const last = recentClientErrorAt.get(key);
  if (last === undefined) return false;
  pruneRecentClientErrorFingerprints(now);
  return now - last < CLIENT_ERROR_LOG_DEDUPE_MS;
}

function beginClientErrorLogAttempt(key: string): void {
  inflightClientErrorLogs.add(key);
}

function finishClientErrorLogAttempt(key: string): void {
  inflightClientErrorLogs.delete(key);
}

function queueClientErrorLogRetry(key: string, now: number = Date.now()): void {
  const queued = queuedClientErrorLogs.get(key);
  queuedClientErrorLogs.set(key, {
    count: (queued?.count ?? 0) + 1,
    latestQueuedAt: now,
  });
}

function takeQueuedClientErrorLogRetries(
  key: string,
): { count: number; latestQueuedAt: number } | null {
  const queued = queuedClientErrorLogs.get(key);
  if (!queued) return null;
  queuedClientErrorLogs.delete(key);
  return queued;
}

function restoreQueuedClientErrorLogRetries(
  key: string,
  queued: { count: number; latestQueuedAt: number },
): void {
  if (queued.count <= 0) return;
  queuedClientErrorLogs.set(key, queued);
}

function markClientErrorLogged(key: string, now: number = Date.now()): void {
  recentClientErrorAt.set(key, now);
  pruneRecentClientErrorFingerprints(now);
}

function normalizeClientErrorLogInput(
  message: string,
  error?: unknown,
  details?: string,
): { normalizedMessage: string; resolvedDetails?: string | undefined } | null {
  const normalizedMessage = message.trim();
  if (!normalizedMessage) return null;
  const resolvedDetails = (details?.trim() || toIpcErrorMessage(error)).trim() || undefined;
  return { normalizedMessage, resolvedDetails };
}

async function appendClientErrorLogInternal(
  source: string,
  normalizedMessage: string,
  resolvedDetails: string | undefined,
  error: unknown,
  level: ClientErrorLogLevel,
): Promise<boolean> {
  try {
    await (appendErrorLogImpl ?? appendErrorLogDefault)(source, normalizedMessage, resolvedDetails, level);
    return true;
  } catch (appendError) {
    emitClientErrorLogFallback(source, normalizedMessage, resolvedDetails, appendError, error);
    return false;
  }
}

function emitClientErrorLogFallback(
  source: string,
  normalizedMessage: string,
  resolvedDetails: string | undefined,
  appendError: unknown,
  originalError: unknown,
): void {
  console.error(`[client-error-log:${source}] ${normalizedMessage}`, {
    details: resolvedDetails,
    appendError,
    originalError,
  });
}

export function appendClientErrorLog(
  source: string,
  message: string,
  error?: unknown,
  details?: string,
  level: ClientErrorLogLevel = 'error',
): Promise<boolean> {
  if (!appendErrorLogImpl && !isTauriRuntimeAvailable()) return Promise.resolve(false);
  const normalized = normalizeClientErrorLogInput(message, error, details);
  if (!normalized) return Promise.resolve(false);
  return appendClientErrorLogInternal(
    source,
    normalized.normalizedMessage,
    normalized.resolvedDetails,
    error,
    level,
  );
}

export function reportClientError(
  source: string,
  message: string,
  error?: unknown,
  details?: string,
  level: ClientErrorLogLevel = 'error',
): void {
  if (!appendErrorLogImpl && !isTauriRuntimeAvailable()) return;
  const normalized = normalizeClientErrorLogInput(message, error, details);
  if (!normalized) return;
  const fingerprint = `${source}:${normalized.normalizedMessage}:${normalized.resolvedDetails ?? ''}`;
  const now = Date.now();
  if (inflightClientErrorLogs.has(fingerprint)) {
    queueClientErrorLogRetry(fingerprint, now);
    return;
  }
  if (shouldSkipClientErrorLog(fingerprint, now)) return;
  const attemptStartedAt = now;
  beginClientErrorLogAttempt(fingerprint);
  let logged = false;
  void appendClientErrorLogInternal(source, normalized.normalizedMessage, normalized.resolvedDetails, error, level)
    .then((didLog) => {
      logged = didLog;
      if (didLog) {
        markClientErrorLogged(fingerprint, attemptStartedAt);
      }
    })
    .finally(() => {
      finishClientErrorLogAttempt(fingerprint);
      const queuedRetries = takeQueuedClientErrorLogRetries(fingerprint);
      if (!queuedRetries) return;
      if (!logged) {
        restoreQueuedClientErrorLogRetries(fingerprint, {
          count: queuedRetries.count - 1,
          latestQueuedAt: queuedRetries.latestQueuedAt,
        });
        reportClientError(source, message, error, details, level);
        return;
      }
      if (queuedRetries.latestQueuedAt - attemptStartedAt >= CLIENT_ERROR_LOG_DEDUPE_MS) {
        reportClientError(source, message, error, details, level);
      }
    });
}

export function resetClientErrorLogDedupeForTests(): void {
  recentClientErrorAt.clear();
  inflightClientErrorLogs.clear();
  queuedClientErrorLogs.clear();
}

export function setAppendErrorLogForTests(next: AppendErrorLogFn | null): void {
  appendErrorLogImpl = next;
}
