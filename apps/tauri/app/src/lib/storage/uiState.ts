import { tryParseJson } from '../security/jsonParse';
import { createBrowserUIStateStorageHost } from './uiState.runtime';

const PREFIX = 'lorvex:';
const uiStateStorageHost = createBrowserUIStateStorageHost();

/**
 * Read a UI-state value from localStorage.
 *
 * The validator asserts the parsed JSON actually matches the expected
 * shape. A stored value written by an older version of the app or
 * hand-edited in devtools must fall back exactly like a parse failure
 * instead of silently poisoning downstream logic that trusts the shape.
 *
 * Example:
 *     const layout = getUIState<DashboardLayout>(
 *       'dashboard.layout',
 *       defaultLayout,
 *       isDashboardLayout,
 *     );
 *
 * The validator signature returns `value is T` (a type predicate) so
 * TypeScript narrows correctly without an explicit cast.
 */
export function getUIState<T>(
  key: string,
  fallback: T,
  validator: (value: unknown) => value is T,
): T {
  try {
    const raw = uiStateStorageHost.getStorage()?.getItem(`${PREFIX}${key}`);
    if (raw == null) return fallback;
    const parseResult = tryParseJson(raw);
    if (!parseResult.ok) return fallback;
    return validator(parseResult.value) ? parseResult.value : fallback;
  } catch {
    return fallback;
  }
}

export function setUIState<T>(key: string, value: T): void {
  try {
    uiStateStorageHost.getStorage()?.setItem(`${PREFIX}${key}`, JSON.stringify(value));
  } catch { /* storage full or unavailable */ }
}

export function removeUIState(key: string): void {
  try {
    uiStateStorageHost.getStorage()?.removeItem(`${PREFIX}${key}`);
  } catch { /* ignore */ }
}

function parseStoredBoolean(raw: string | null | undefined, fallback: boolean): boolean {
  if (raw == null) return fallback;
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  return fallback;
}

export function getUIStateBoolean(key: string, fallback: boolean): boolean {
  try {
    const raw = uiStateStorageHost.getStorage()?.getItem(`${PREFIX}${key}`);
    return parseStoredBoolean(raw, fallback);
  } catch {
    return fallback;
  }
}

export function setUIStateBoolean(key: string, value: boolean): void {
  setUIState(key, value);
}

export function getUIStateString(key: string, fallback: string): string {
  try {
    const raw = uiStateStorageHost.getStorage()?.getItem(`${PREFIX}${key}`);
    if (raw == null) return fallback;
    const parseResult = tryParseJson(raw);
    if (!parseResult.ok) return fallback;
    return typeof parseResult.value === 'string' ? parseResult.value : fallback;
  } catch {
    return fallback;
  }
}
