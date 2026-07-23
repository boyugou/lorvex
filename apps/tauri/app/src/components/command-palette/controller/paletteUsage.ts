/**
 * Lightweight, localStorage-backed activity log for the command
 * palette. Tracks which palette entries the user activates (by stable
 * `kind:identifier` key) so the empty-query state can surface the five
 * most-recently-activated entries; tracks which tasks the user opens
 * (by task id + observed title) so the empty state can also surface
 * the three most-frequently-opened tasks.
 *
 * Why localStorage rather than a SQLite-backed device-state row:
 *   - The data is purely UI-local (frequency hints), not synced.
 *   - Loss on storage wipe is benign — the next interaction repopulates.
 *   - Lets the read happen synchronously during a `useMemo` so the
 *     empty-query state never flickers from "no recents" → "recents".
 *
 * Capped at 20 recent activations and 50 task-open entries so the
 * JSON payload stays under a few kilobytes even for power users.
 */

const RECENT_ACTIVATIONS_KEY = 'lorvex.palette.recentActivations.v1';
const TASK_OPENS_KEY = 'lorvex.palette.taskOpens.v1';

const MAX_RECENT_ACTIVATIONS = 20;
const MAX_TASK_OPEN_ENTRIES = 50;

export interface RecentPaletteActivation {
  /**
   * Stable identity for the activated palette entry. Format matches
   * `resultIdentity()`: `kind:label` for nav/action items, `task:<id>`
   * for tasks. Tasks are tracked separately via `recordTaskOpen` so
   * the frequency hint can be computed without scanning the activation
   * log.
   */
  key: string;
  /** Human-visible label captured at activation time. */
  label: string;
  /**
   * Result kind so the empty-state row can re-render the matching icon
   * + section heading. Mirrors `ResultItem['kind']`.
   */
  kind: 'nav' | 'action' | 'task';
  /** Unix ms of the activation. */
  timestamp: number;
}

export interface TaskOpenEntry {
  taskId: string;
  /**
   * Title observed at the time of opening — stored so we can still
   * label the row when the task is no longer in the current query
   * result set. Refreshed on every open.
   */
  title: string;
  /** Total opens recorded for this task across the cap window. */
  count: number;
  /** Unix ms of the most recent open — breaks frequency ties. */
  lastOpened: number;
}

function safeReadJson<T>(key: string): T | null {
  try {
    if (typeof window === 'undefined') return null;
    const raw = window.localStorage.getItem(key);
    if (!raw) return null;
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

function safeWriteJson<T>(key: string, value: T): void {
  try {
    if (typeof window === 'undefined') return;
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Storage may be disabled (private mode, quota). The frequency
    // hint is best-effort — dropping the write means we just won't
    // show recents next time, which is acceptable.
  }
}

export function listRecentPaletteActivations(): RecentPaletteActivation[] {
  const raw = safeReadJson<RecentPaletteActivation[]>(RECENT_ACTIVATIONS_KEY);
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((entry): entry is RecentPaletteActivation =>
      !!entry
      && typeof entry.key === 'string'
      && typeof entry.label === 'string'
      && (entry.kind === 'nav' || entry.kind === 'action' || entry.kind === 'task')
      && typeof entry.timestamp === 'number',
    )
    .slice(0, MAX_RECENT_ACTIVATIONS);
}

export function recordPaletteActivation(entry: Omit<RecentPaletteActivation, 'timestamp'>): void {
  // Skip tasks — their frequency is tracked via `recordTaskOpen`
  // because we care about "how often" not just "last opened". Surfaced
  // separately in the empty state under "Frequent tasks".
  if (entry.kind === 'task') return;
  const current = listRecentPaletteActivations();
  const next: RecentPaletteActivation[] = [
    { ...entry, timestamp: Date.now() },
    ...current.filter((row) => row.key !== entry.key),
  ].slice(0, MAX_RECENT_ACTIVATIONS);
  safeWriteJson(RECENT_ACTIVATIONS_KEY, next);
}

export function listTaskOpens(): TaskOpenEntry[] {
  const raw = safeReadJson<TaskOpenEntry[]>(TASK_OPENS_KEY);
  if (!Array.isArray(raw)) return [];
  return raw.filter((entry): entry is TaskOpenEntry =>
    !!entry
    && typeof entry.taskId === 'string'
    && typeof entry.title === 'string'
    && typeof entry.count === 'number'
    && typeof entry.lastOpened === 'number',
  );
}

export function recordTaskOpen(taskId: string, title: string): void {
  const current = listTaskOpens();
  const idx = current.findIndex((entry) => entry.taskId === taskId);
  const now = Date.now();
  let next: TaskOpenEntry[];
  if (idx >= 0) {
    const existing = current[idx]!;
    const updated: TaskOpenEntry = {
      taskId,
      title,
      count: existing.count + 1,
      lastOpened: now,
    };
    next = [updated, ...current.slice(0, idx), ...current.slice(idx + 1)];
  } else {
    next = [{ taskId, title, count: 1, lastOpened: now }, ...current];
  }
  // Trim to cap, preferring most-recent + most-frequent over the
  // long tail.
  next.sort((a, b) => {
    if (b.count !== a.count) return b.count - a.count;
    return b.lastOpened - a.lastOpened;
  });
  next = next.slice(0, MAX_TASK_OPEN_ENTRIES);
  safeWriteJson(TASK_OPENS_KEY, next);
}

/**
 * Pure helper consumed by `results.ts` — selects the top-N tasks by
 * frequency from a stored set, returning them in the order they
 * should render.
 */
export function topFrequentTasks(entries: TaskOpenEntry[], limit: number): TaskOpenEntry[] {
  return [...entries]
    .sort((a, b) => {
      if (b.count !== a.count) return b.count - a.count;
      return b.lastOpened - a.lastOpened;
    })
    .slice(0, limit);
}
