export const SQLITE_BUSY_RETRY_BASE_DELAYS_MS = [0, 50, 100, 200, 400, 800, 1600] as const;

export const SQLITE_BUSY_RETRY_JITTER_FRACTION = 0.2;

export function computeJitteredBusyRetryDelay(
  baseMs: number,
  randomValue: number,
): number {
  if (baseMs <= 0) return 0;
  const variance = baseMs * SQLITE_BUSY_RETRY_JITTER_FRACTION;
  return baseMs + (randomValue * 2 - 1) * variance;
}

export function isRetryableSqliteBusyMessage(message: string): boolean {
  const lower = message.toLowerCase();
  return lower.includes('database is locked')
    || lower.includes('database busy')
    || lower.includes('sql_busy');
}
