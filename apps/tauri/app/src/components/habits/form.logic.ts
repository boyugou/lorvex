const HABIT_TARGET_COUNT_MIN = 1;
const HABIT_TARGET_COUNT_MAX = 50;
const DECIMAL_INTEGER = /^\d+$/;

function clampHabitTargetCount(value: number): number {
  return Math.min(HABIT_TARGET_COUNT_MAX, Math.max(HABIT_TARGET_COUNT_MIN, value));
}

export function normalizeHabitTargetCountValue(value: number): number {
  if (!Number.isFinite(value)) return HABIT_TARGET_COUNT_MIN;
  return clampHabitTargetCount(Math.floor(value));
}

export function normalizeHabitTargetCountInput(raw: string): number {
  const trimmed = raw.trim();
  if (!trimmed) return HABIT_TARGET_COUNT_MIN;
  if (!DECIMAL_INTEGER.test(trimmed)) return HABIT_TARGET_COUNT_MIN;

  const parsed = Number(trimmed);
  if (!Number.isSafeInteger(parsed)) return HABIT_TARGET_COUNT_MIN;

  return clampHabitTargetCount(parsed);
}
