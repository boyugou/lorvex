import { useCallback, useState } from 'react';
import { tryParseJson } from '../security/jsonParse';
import { getUIState, setUIState } from './uiState';

/**
 * Persist a piece of view-state to a per-view localStorage key
 * (mirrors the `quickCapture:lastListId` pattern), so list-style
 * views (AllTasksView, UpcomingView, EisenhowerView, KanbanView)
 * survive a page reload or a hop out and back without dropping the
 * user's filter pills, search query, time horizon, and view mode.
 *
 * Behavior:
 *   - On first render the hook reads the persisted value and validates
 *     it via `validate`. Anything else (missing, malformed JSON, wrong
 *     shape) falls back to `defaultValue`.
 *   - The setter signature mirrors React's `useState` so callers can
 *     swap `useState(x)` → `useLocalStorageBackedState(key, x, isX)`
 *     without touching downstream code.
 *   - Writes go through `setUIState` (prefixed with `lorvex:` and
 *     JSON-encoded). Storage failures (private mode, quota) are
 *     swallowed inside `setUIState` itself — losing persistence is
 *     non-fatal, the in-memory state still works.
 */
export function useLocalStorageBackedState<T>(
  key: string,
  defaultValue: T,
  validate: (value: unknown) => value is T,
): [T, React.Dispatch<React.SetStateAction<T>>] {
  const [state, setState] = useState<T>(() =>
    getUIState<T>(key, defaultValue, validate),
  );

  const update = useCallback(
    (next: React.SetStateAction<T>) => {
      setState((prev) => {
        const value = typeof next === 'function' ? (next as (p: T) => T)(prev) : next;
        setUIState(key, value);
        return value;
      });
    },
    [key],
  );

  return [state, update];
}

/**
 * Validator for `Set<string>` values stored as JSON arrays. Sets aren't
 * JSON-native, so we serialize them as arrays on the way out and re-
 * hydrate on read. Mirrors the convention already used by
 * `useCollapsibleSections` (which stores `Set<string>` as `string[]`).
 */
export function isStringArray(value: unknown): value is string[] {
  if (!Array.isArray(value)) return false;
  return value.every((item) => typeof item === 'string');
}

export function isStringOrNull(value: unknown): value is string | null {
  return value === null || typeof value === 'string';
}

export function isNumberOrNull(value: unknown): value is number | null {
  return value === null || typeof value === 'number';
}

export function isString(value: unknown): value is string {
  return typeof value === 'string';
}

export function isOneOf<T extends string>(
  options: readonly T[],
): (value: unknown) => value is T {
  return (value): value is T => typeof value === 'string' && (options as readonly string[]).includes(value);
}

/**
 * Read-only helper used by the view tests: parse a raw localStorage
 * string and return the validated value or null. Re-exported so unit
 * tests can verify persistence without spinning up `localStorage`.
 */
export function readPersistedState<T>(
  raw: string | null,
  validate: (value: unknown) => value is T,
): T | null {
  if (raw == null) return null;
  const parsed = tryParseJson(raw);
  if (!parsed.ok) return null;
  return validate(parsed.value) ? parsed.value : null;
}
