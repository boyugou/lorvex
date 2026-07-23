/**
 * Minimal module-level toast store.
 * Components call `toast.success()` / `toast.error()` / `toast.warning()` /
 * `toast.info()` directly — no Context needed. `ToastContainer` subscribes
 * via `useToasts()`.
 *
 * Deduplication strategy (type-based):
 *   Each of the four channels — success, error, warning, info — has its
 *   own dedup window keyed on `type:message[:context]`. A repeat firing
 *   of the same key inside its window is suppressed (with one carve-out:
 *   a newly arrived actionable variant upgrades a non-actionable in
 *   flight, so a later "Sync failed — Retry" never gets shadowed by an
 *   earlier opaque "Sync failed").
 *
 *   The per-type windows live in `DEDUPE_WINDOW_BY_TYPE` (see
 *   `./durations.ts`); they are bound to the corresponding on-screen
 *   display durations so the next duplicate cannot arrive while the
 *   original is still visible.
 *
 * Subtree layout:
 *   - `types.ts`               — `ToastType` / `ToastItem` / `ToastAction` / options
 *   - `durations.ts`           — per-type durations, dedup windows, length-scaling
 *   - `store.ts`               — module state, dedup, eviction, dismiss/remove,
 *                                pause/resume, `show`, test hooks
 *   - `api.ts`                 — public `toast` object (`.success`/`.error`/...)
 *   - `triggerLatestUndo.ts`   — global ⌘Z keyboard entry point
 *   - `hook.ts`                — `useToasts` React subscriber
 */

export type { ToastItem } from './types';
export { MAX_TOASTS } from './durations';
export {
  __getToastsForTests,
  __resetToastsForTests,
  __setToastTimerHostForTests,
  dismissToast,
  dismissToastsByContext,
  getToastDismissState,
  pauseToastDismiss,
  removeToast,
  resumeToastDismiss,
} from './store';
export { toast } from './api';
export { triggerLatestUndo } from './triggerLatestUndo';
export { useToasts } from './hook';
