// Pure logic for the "hide completed tasks older than N days" list-view
// filter introduced for Kept free of React so it can be unit-tested
// in the Node-based runtime test suite without a DOM or component tree.

/** Default cutoff when the preference is absent or unparseable. */
export const DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS = 30;

/** Clamp bounds mirrored by the settings UI input. */
export const MIN_HIDE_COMPLETED_OLDER_THAN_DAYS = 0;
export const MAX_HIDE_COMPLETED_OLDER_THAN_DAYS = 3650;

interface HideCompletedCandidate {
  /** ISO 8601 completion timestamp, or null if the task is not completed. */
  completed_at: string | null;
}

/**
 * Parse the raw preference value. Accepts canonical decimal integer
 * payloads written by `setPreference`. Returns the default when the value
 * is missing, malformed, or outside bounds.
 */
export function parseHideCompletedOlderThanDays(raw: string | null): number {
  if (raw == null) return DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS;
  const trimmed = raw.trim();
  if (trimmed === '') return DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS;
  if (!/^\d+$/.test(trimmed)) return DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS;
  const parsed = Number(trimmed);
  return clampHideCompletedOlderThanDays(parsed);
}

export function clampHideCompletedOlderThanDays(value: number): number {
  if (!Number.isFinite(value)) return DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS;
  const rounded = Math.trunc(value);
  if (rounded < MIN_HIDE_COMPLETED_OLDER_THAN_DAYS) {
    return MIN_HIDE_COMPLETED_OLDER_THAN_DAYS;
  }
  if (rounded > MAX_HIDE_COMPLETED_OLDER_THAN_DAYS) {
    return MAX_HIDE_COMPLETED_OLDER_THAN_DAYS;
  }
  return rounded;
}

/**
 * The inclusive cutoff in milliseconds — any completion timestamp older
 * than `now - days * 86_400_000` is considered out-of-window. Returns
 * null when `days` is 0 (meaning "always show, never hide"). Surfaced as
 * a helper so tests can pin the arithmetic independently of the filter.
 */
export function hideCompletedCutoffMs(nowMs: number, days: number): number | null {
  const safeDays = clampHideCompletedOlderThanDays(days);
  if (safeDays <= 0) return null;
  return nowMs - safeDays * 86_400_000;
}

/**
 * Partition completed tasks into `visible` and `hidden` buckets relative
 * to the cutoff. A completed task with a null or unparseable
 * `completed_at` is always treated as visible — we never hide data we
 * cannot date, to avoid silently swallowing rows with corrupt timestamps.
 */
export function partitionCompletedTasks<T extends HideCompletedCandidate>(
  tasks: readonly T[],
  nowMs: number,
  days: number,
): { visible: T[]; hidden: T[] } {
  const cutoff = hideCompletedCutoffMs(nowMs, days);
  if (cutoff === null) {
    return { visible: [...tasks], hidden: [] };
  }
  const visible: T[] = [];
  const hidden: T[] = [];
  for (const task of tasks) {
    if (task.completed_at == null) {
      visible.push(task);
      continue;
    }
    const completedMs = Date.parse(task.completed_at);
    if (!Number.isFinite(completedMs)) {
      visible.push(task);
      continue;
    }
    if (completedMs >= cutoff) {
      visible.push(task);
    } else {
      hidden.push(task);
    }
  }
  return { visible, hidden };
}
