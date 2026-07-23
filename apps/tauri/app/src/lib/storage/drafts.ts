/**
 * Centralized registry + access layer for component draft state held in
 * `localStorage`.
 *
 * each draft-bearing surface
 * (`daily-review`, `quick-capture`) hand-rolled its own
 * `localStorage.{getItem,setItem,removeItem}` calls. That pattern had
 * two problems:
 *   1. No central place to enumerate draft keys, so a future "Reset
 *      Preferences / Clear All Data" flow had no canonical list to
 *      walk.
 *   2. No quota / private-mode handling — a thrown `setItem` was a
 *      try-catch boilerplate at every site, with subtle drift between
 *      "non-fatal" and "ignore" comments.
 *
 * This module owns those concerns. Drafts continue to be stored as raw
 * strings (NOT JSON-of-JSON like `setUIState` produces) because the
 * existing per-component readers parse the raw payload directly —
 * forcing a double-encode through `setUIState` would either break
 * compatibility or require simultaneous reader rewrites.
 */
import { safeLocalStorage } from './index';
import { removeUIState } from './uiState';

/**
 * Canonical list of every draft key the app writes. New surfaces MUST
 * register their key here so "Reset Preferences" / data-cleanup flows
 * can clear them in one shot via `clearAllDrafts()`.
 *
 * Note: removed draft-bearing surfaces may leave retired keys behind briefly
 * during development. Keep this registry focused on active surfaces.
 */
export const DRAFT_KEYS = {
  dailyReview: 'lorvex.dailyReview.draft',
  quickCapture: 'lorvex.quickCapture.draft',
} as const;

export const UI_STATE_DRAFT_KEYS = {
  sidebarNewList: 'sidebar:newListDraft',
  popoverQuickAdd: 'popover:quickAddText',
} as const;

type StaticDraftKey = (typeof DRAFT_KEYS)[keyof typeof DRAFT_KEYS];
type DraftKey = StaticDraftKey;

/**
 * Read the raw stored string for a draft key, or `null` if no draft is
 * persisted (or storage is unavailable). Storage exceptions are caught
 * and treated the same as a missing entry — losing a draft on a
 * private-mode launch is non-fatal.
 *
 * Callers parse the returned string using their own typed parser
 * (e.g. `readQuickCaptureDraftFromStorageValue`); this module
 * deliberately does NOT validate shape so a draft format change is
 * the parser's problem, not the storage layer's.
 */
export function readDraft(key: DraftKey): string | null {
  try {
    return safeLocalStorage()?.getItem(key) ?? null;
  } catch {
    return null;
  }
}

/**
 * Persist a draft string. Storage failures (private mode, quota
 * exhaustion) are silently swallowed — a draft is best-effort
 * durability, never a correctness contract. Callers that need
 * confirmation should re-read after writing.
 */
export function writeDraft(key: DraftKey, value: string): void {
  try {
    safeLocalStorage()?.setItem(key, value);
  } catch {
    /* storage full or unavailable */
  }
}

/** Remove a single draft entry. Idempotent and exception-safe. */
export function clearDraft(key: DraftKey): void {
  try {
    safeLocalStorage()?.removeItem(key);
  } catch {
    /* ignore */
  }
}

/** Remove every registered draft. */
export function clearAllDrafts(): void {
  const ls = safeLocalStorage();
  if (!ls) return;

  const keysToClear = new Set<string>(Object.values(DRAFT_KEYS));

  for (const key of keysToClear) {
    try {
      ls.removeItem(key);
    } catch {
      /* ignore */
    }
  }

  for (const key of Object.values(UI_STATE_DRAFT_KEYS)) {
    removeUIState(key);
  }
}
