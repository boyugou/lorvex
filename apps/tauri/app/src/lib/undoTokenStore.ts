
import { tryParseJson } from './security/jsonParse';
import { hasOnlyKeys, isPlainRecord as isRecord } from './objectGuards';
import { createBrowserUndoTokenStorageHost } from './undoTokenStore.runtime';

export const UNDO_TOKEN_HOLD_MS = 5000;

/**
 * Categories that map 1:1 to the backend undo_token-emitting commands.
 * `*_batch` variants hold an array of tokens; the single variants hold
 * a single token in a 1-element array. Keeping them as a flat list of
 * tokens lets the redeemer route everything through
 * `undo_task_lifecycle_batch` without caring which shape produced it.
 */
export type RecentUndoAction =
  | 'complete'
  | 'cancel'
  | 'defer'
  | 'complete_batch'
  | 'cancel_batch'
  | 'defer_batch';

export interface RecentUndoToken {
  /** The backend-issued undo token (single-task shape kept one per entry). */
  token: string;
  /** Short human-readable label shown in the command palette. */
  label: string;
  /** Which lifecycle mutation produced this token. */
  action: RecentUndoAction;
  /** Wall-clock ms the token was issued. */
  issuedAt: number;
  /** Wall-clock ms the backend hold expires. */
  expiresAt: number;
}

const STORAGE_KEY = 'lorvex:recent-undo-tokens';
const undoTokenStorageHost = createBrowserUndoTokenStorageHost();
const RECENT_UNDO_ACTIONS = new Set<RecentUndoAction>([
  'complete',
  'cancel',
  'defer',
  'complete_batch',
  'cancel_batch',
  'defer_batch',
]);
const RECENT_UNDO_TOKEN_KEYS = new Set([
  'action',
  'expiresAt',
  'issuedAt',
  'label',
  'token',
]);

/**
 * Defensive cap: under pathological bulk operations (e.g. cancel 500
 * tasks at once, then cancel 500 more within the 5s window), the
 * serialized blob is still trivially small, but we never want an
 * unbounded list leaking into localStorage if the clock is wrong or
 * the user is on a fast machine producing sub-ms entries.
 */
const MAX_ENTRIES = 50;

function readRaw(storage: Storage): RecentUndoToken[] {
  try {
    const raw = storage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parseResult = tryParseJson(raw);
    if (!parseResult.ok) return [];
    if (!Array.isArray(parseResult.value)) return [];
    if (!parseResult.value.every(isValidEntry)) return [];
    return parseResult.value;
  } catch {
    return [];
  }
}

function hasOnlyRecentUndoTokenKeys(value: Record<string, unknown>): boolean {
  return hasOnlyKeys(value, RECENT_UNDO_TOKEN_KEYS);
}

function isRecentUndoAction(value: unknown): value is RecentUndoAction {
  return typeof value === 'string' && RECENT_UNDO_ACTIONS.has(value as RecentUndoAction);
}

function isValidEntry(value: unknown): value is RecentUndoToken {
  if (!isRecord(value)) return false;
  if (!hasOnlyRecentUndoTokenKeys(value)) return false;
  const entry = value;
  return (
    typeof entry.token === 'string' && entry.token.length > 0
    && typeof entry.label === 'string'
    && isRecentUndoAction(entry.action)
    && typeof entry.issuedAt === 'number' && Number.isSafeInteger(entry.issuedAt)
    && typeof entry.expiresAt === 'number' && Number.isSafeInteger(entry.expiresAt)
    && entry.expiresAt > entry.issuedAt
  );
}

function writeRaw(storage: Storage, entries: RecentUndoToken[]): void {
  try {
    storage.setItem(STORAGE_KEY, JSON.stringify(entries));
  } catch {
    // Quota exceeded or storage disabled — drop silently. The undo
    // toast closure is still live for the current session, so the
    // worst case is degraded (but not broken) UX.
  }
}

function pruneExpired(entries: RecentUndoToken[], now: number): RecentUndoToken[] {
  return entries.filter((entry) => entry.expiresAt > now);
}

/**
 * Record a newly-issued undo token. De-dupes by token and bounds the
 * total entry count. Pruning expired entries is intentionally the
 * reader's job (see `listRecentUndoTokens`) — this keeps the write
 * path independent of the wall clock so a caller supplying explicit
 * timestamps (e.g. tests, time-travel debugging) never has entries
 * silently dropped at insert time.
 */
export function recordUndoToken(entry: RecentUndoToken): void {
  const storage = undoTokenStorageHost.getStorage();
  if (!storage) return;
  const existing = readRaw(storage);
  // De-dupe by token — a caller that retries the same write should
  // not produce two palette entries for the same backend token.
  const filtered = existing.filter((e) => e.token !== entry.token);
  const merged = [...filtered, entry];
  // If we're somehow above the cap, drop the oldest first.
  const bounded = merged.length > MAX_ENTRIES ? merged.slice(merged.length - MAX_ENTRIES) : merged;
  writeRaw(storage, bounded);
}

/**
 * List currently-active undo tokens, sorted by most recently issued
 * first. Prunes expired entries as a side effect so consumers never
 * see stale rows even if no write has happened recently.
 */
export function listRecentUndoTokens(now: number = Date.now()): RecentUndoToken[] {
  const storage = undoTokenStorageHost.getStorage();
  if (!storage) return [];
  const entries = readRaw(storage);
  const live = pruneExpired(entries, now);
  if (live.length !== entries.length) {
    writeRaw(storage, live);
  }
  // Most recent first so the palette can present the latest action at
  // the top of the "Recent actions → Undo" group.
  return [...live].sort((a, b) => b.issuedAt - a.issuedAt);
}

/** Remove a token after successful redemption (or if the caller knows
 * it has already been consumed by the backend). */
export function consumeUndoToken(token: string): void {
  const storage = undoTokenStorageHost.getStorage();
  if (!storage) return;
  const existing = readRaw(storage);
  const remaining = existing.filter((entry) => entry.token !== token);
  if (remaining.length === existing.length) return;
  writeRaw(storage, remaining);
}

/**
 * Helper used by `recordUndoToken` callers to produce consistent
 * expiry timestamps. Centralized so a future tweak to
 * `UNDO_TOKEN_HOLD_MS` does not require hunting through every emitter.
 */
export function makeRecentUndoToken(
  token: string,
  label: string,
  action: RecentUndoAction,
  now: number = Date.now(),
): RecentUndoToken {
  return {
    token,
    label,
    action,
    issuedAt: now,
    expiresAt: now + UNDO_TOKEN_HOLD_MS,
  };
}

export function clearUndoTokens(): void {
  const storage = undoTokenStorageHost.getStorage();
  if (!storage) return;
  try {
    storage.removeItem(STORAGE_KEY);
  } catch {
    // Best-effort test/dev cleanup; storage may be unavailable.
  }
}

export const __TEST_ONLY__ = {
  STORAGE_KEY,
};
