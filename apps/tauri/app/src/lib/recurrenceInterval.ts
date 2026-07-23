export const RECURRENCE_INTERVAL_MIN = 1;
export const RECURRENCE_INTERVAL_MAX = 99;

const DECIMAL_INTEGER = /^\d+$/;

function clampRecurrenceInterval(value: number): number {
  return Math.min(RECURRENCE_INTERVAL_MAX, Math.max(RECURRENCE_INTERVAL_MIN, value));
}

export function normalizeRecurrenceIntervalValue(value: number): number {
  if (!Number.isFinite(value)) return RECURRENCE_INTERVAL_MIN;
  return clampRecurrenceInterval(Math.floor(value));
}

export function normalizeRecurrenceIntervalInput(raw: string): number {
  const trimmed = raw.trim();
  if (!trimmed) return RECURRENCE_INTERVAL_MIN;
  if (!DECIMAL_INTEGER.test(trimmed)) return RECURRENCE_INTERVAL_MIN;

  const parsed = Number(trimmed);
  if (!Number.isSafeInteger(parsed)) return RECURRENCE_INTERVAL_MIN;

  return clampRecurrenceInterval(parsed);
}
