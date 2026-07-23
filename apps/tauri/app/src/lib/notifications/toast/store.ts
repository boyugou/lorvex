/**
 * Module-level toast store, dedup map, and timer bookkeeping.
 *
 * Holds the single mutable `toasts` array consumed by the React subscriber
 * in `hook.ts` and by the public `toast` API in `api.ts`. Owns the
 * timer-host indirection (browser scheduling by default; tests swap it
 * via `__setToastTimerHostForTests`), the per-toast safety-fallback
 * cancellers used by `dismissToast`, and the auto-dismiss timer state
 * the hover-pause / resume path suspends.
 *
 * Public surface (re-exported from the `toast` barrel): `dismissToast`,
 * `removeToast`, `dismissToastsByContext`, `pauseToastDismiss`,
 * `resumeToastDismiss`, `getToastDismissState`.
 */

import {
  createBrowserToastTimerHost,
  scheduleToastTimer,
  type ToastTimerHost,
} from '../toast.runtime';
import {
  DEDUPE_WINDOW_BY_TYPE,
  EXIT_TRANSITION_MS,
  MAX_TOASTS,
} from './durations';
import type { ToastAction, ToastItem, ToastListener, ToastType } from './types';

// ---------------------------------------------------------------------------
// Store state
// ---------------------------------------------------------------------------

let toasts: ToastItem[] = [];
const listeners = new Set<ToastListener>();
const recentToastAt = new Map<string, number>();

let toastTimerHost: ToastTimerHost = createBrowserToastTimerHost();

/**
 * Per-toast cancel handles for the safety-fallback timer in
 * `dismissToast`. Without a cancel, every dismissed toast scheduled an
 * `EXIT_TRANSITION_MS` timeout that fired AFTER `transitionend` had
 * already removed the toast — harmless but wasted timer pressure that
 * accumulated under tight error-storm loops.
 */
const safetyCancellers = new Map<string, () => void>();

interface ToastDismissState {
  totalMs: number;
  remainingMs: number;
  startedAt: number;
  cancel: () => void;
}
const dismissTimers = new Map<string, ToastDismissState>();
const noopCancel = () => undefined;

// ---------------------------------------------------------------------------
// Subscription primitives
// ---------------------------------------------------------------------------

/** Snapshot of the current toast list for direct readers (the React hook
 *  takes a copy on mount). */
export function getToastsSnapshot(): ToastItem[] {
  return [...toasts];
}

/** Subscribe to toast-list changes. Returns an unsubscribe handle. */
export function subscribeToToasts(listener: ToastListener): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function notify() {
  const snapshot = [...toasts];
  listeners.forEach((l) => l(snapshot));
}

// ---------------------------------------------------------------------------
// Iteration helper for `triggerLatestUndo`
// ---------------------------------------------------------------------------

/** Return the most recently inserted toast that is not yet dismissing
 *  and carries an action. Used by the global ⌘Z/Ctrl+Z handler. */
export function findLatestActionableToast(): ToastItem | undefined {
  for (let i = toasts.length - 1; i >= 0; i--) {
    const t = toasts[i];
    if (t && t.action && !t.dismissing) return t;
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Dismiss / remove
// ---------------------------------------------------------------------------

/** Mark a toast as dismissing (starts CSS exit animation).
 *  The ToastContainer calls `removeToast` when transitionend fires,
 *  or a safety timeout removes it after `EXIT_TRANSITION_MS`. */
export function dismissToast(id: string): void {
  const t = toasts.find((x) => x.id === id);
  if (!t || t.dismissing) return;
  toasts = toasts.map((x) => (x.id === id ? { ...x, dismissing: true } : x));
  notify();
  // Safety fallback: remove after the transition even if
  // `transitionend` doesn't fire. The returned cancel is stashed so
  // `removeToast` (whether triggered by `transitionend` or the
  // safety fallback itself) can suppress the redundant second fire.
  safetyCancellers.set(
    id,
    scheduleToastTimer(toastTimerHost, () => removeToast(id), EXIT_TRANSITION_MS),
  );
}

/** Fully remove a toast from the store (called after exit animation completes). */
export function removeToast(id: string): void {
  // Cancel the safety fallback first so a successful `transitionend`
  // path doesn't leave a redundant `removeToast(id)` queued in the
  // timer wheel.
  const cancel = safetyCancellers.get(id);
  if (cancel !== undefined) {
    safetyCancellers.delete(id);
    cancel();
  }
  // Drop the auto-dismiss bookkeeping once the toast is gone so a
  // stale hover-pause on a removed id cannot resurrect timers.
  const dismissState = dismissTimers.get(id);
  if (dismissState) {
    dismissState.cancel();
    dismissTimers.delete(id);
  }
  const before = toasts.length;
  toasts = toasts.filter((t) => t.id !== id);
  if (toasts.length !== before) notify();
}

export function dismissToastsByContext(context: string): void {
  for (const key of recentToastAt.keys()) {
    if (key.endsWith(`:${context}`)) {
      recentToastAt.delete(key);
    }
  }
  for (const item of toasts) {
    if (item.context === context && !item.dismissing) {
      dismissToast(item.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Auto-dismiss pause / resume / inspect
// ---------------------------------------------------------------------------

/** Pause the auto-dismiss countdown for a toast. No-op if already paused
 *  or no timer is registered. */
export function pauseToastDismiss(id: string): void {
  const state = dismissTimers.get(id);
  if (!state) return;
  state.cancel();
  const elapsed = Date.now() - state.startedAt;
  state.remainingMs = Math.max(0, state.remainingMs - elapsed);
  // Mark paused by reusing cancel as a no-op.
  state.cancel = noopCancel;
}

/** Resume the auto-dismiss countdown for a toast using the remaining ms
 *  captured by the latest pause. No-op if the toast was never tracked. */
export function resumeToastDismiss(id: string): void {
  const state = dismissTimers.get(id);
  if (!state) return;
  if (state.remainingMs <= 0) {
    dismissToast(id);
    return;
  }
  state.startedAt = Date.now();
  state.cancel = scheduleToastTimer(
    toastTimerHost,
    () => dismissToast(id),
    state.remainingMs,
  );
}

/** Read the dismiss state for the renderer's progress bar. Returns
 *  null if the toast is not tracked (e.g. a test that didn't go through
 *  `show`). */
export function getToastDismissState(
  id: string,
): { totalMs: number; remainingMs: number; running: boolean } | null {
  const state = dismissTimers.get(id);
  if (!state) return null;
  // `running` is approximated by the presence of an active cancel —
  // paused state replaces cancel with a no-op, but exposing the
  // distinction lets the renderer freeze the bar.
  const running = state.cancel !== noopCancel;
  const elapsed = running ? Date.now() - state.startedAt : 0;
  const remainingMs = Math.max(0, state.remainingMs - elapsed);
  return { totalMs: state.totalMs, remainingMs, running };
}

// ---------------------------------------------------------------------------
// Insert (`show`) — the only writer for `toasts` outside dismiss/remove
// ---------------------------------------------------------------------------

/**
 * Insert a toast, honoring the per-type dedup window and the
 * `MAX_TOASTS` eviction order. Schedules an auto-dismiss timer at
 * `durationMs` and records the entry in `dismissTimers` so the
 * hover-pause / resume path can suspend the countdown.
 *
 * @param context  Optional discriminator so the same message text can show for
 *                 different logical events (e.g. pass a task ID when showing
 *                 "Task completed" for distinct tasks).
 */
export function show(
  message: string,
  type: ToastType,
  durationMs: number,
  action?: ToastAction,
  context?: string,
  priority?: boolean,
): void {
  const now = Date.now();
  // Include context in the dedup key so "Task completed" for task-A and task-B
  // are treated as separate toasts even within the dedup window.
  // also fold action-presence into the key when no explicit
  // context is supplied so two unrelated `toast.error(t('common.error'))`
  // calls — one bare, one carrying a Retry action — don't silently
  // collapse the actionable variant onto the non-actionable one.
  // Callers that want strict dedup should pass an explicit `context`.
  const actionMarker = context ? '' : action ? '#a' : '#p';
  const key = context
    ? `${type}:${message}:${context}`
    : `${type}:${message}${actionMarker}`;
  const last = recentToastAt.get(key) ?? 0;
  const dedupeWindow = DEDUPE_WINDOW_BY_TYPE[type];
  if (now - last < dedupeWindow) {
    // Never let a non-actionable toast suppress a newly arrived
    // actionable variant of the same message. E.g. an opaque
    // "Sync failed" info-toast fires, then the retry path produces a
    // richer "Sync failed — Retry" actionable error; dropping the
    // second one would cost the user the only Retry affordance. When
    // the new toast carries an action, scan the visible stack: if
    // an existing same-keyed toast lacks an action, dismiss it so
    // the new actionable one can take its place without duplicating
    // the message text. Two important properties:
    //   1. We bypass the dedupe `return` and let the standard insert
    //      path schedule its own auto-dismiss timer at the (length-
    //      scaled) actionable duration — no risk of the original
    //      shorter timer cutting the action button off early.
    //   2. We refresh `recentToastAt` so a *third* identical actionable
    //      toast still gets deduped against this one (preserves the
    //      retry-storm guard).
    if (action) {
      let foundUpgrade = false;
      for (const candidate of toasts) {
        if (
          !candidate.dismissing &&
          !candidate.action &&
          candidate.type === type &&
          candidate.message === message
        ) {
          dismissToast(candidate.id);
          foundUpgrade = true;
          break;
        }
      }
      if (foundUpgrade) {
        recentToastAt.set(key, now);
        // Fall through to the normal insert path below.
      } else {
        return;
      }
    } else {
      return;
    }
  } else {
    recentToastAt.set(key, now);
  }

  const id = Math.random().toString(36).slice(2, 9);
  toasts = [...toasts, { id, message, type, action, context, priority, durationMs }];
  // when the stack exceeds MAX_TOASTS, evict in
  // this order of preference:
  //   1. Oldest non-actionable, non-priority toast (plain info/success).
  //   2. Oldest actionable but non-priority toast (single-task undo).
  //   3. Oldest priority toast — only if ALL remaining are priority.
  //
  // Rationale: a coalesced bulk-undo toast ("Undo all 20 completions")
  // represents 20 actions behind a single token. Losing it to a drip
  // of single-task success toasts would silently strip the only undo
  // path for those 20 tasks — far worse than dropping a chatty info
  // toast. Single-task undo still beats plain info, but loses
  // to a bulk-undo when the stack is saturated.
  while (toasts.length > MAX_TOASTS) {
    const plainIdx = toasts.findIndex((t) => !t.action && !t.priority && !t.dismissing);
    if (plainIdx >= 0) {
      toasts = [...toasts.slice(0, plainIdx), ...toasts.slice(plainIdx + 1)];
      continue;
    }
    const actionableNonPriorityIdx = toasts.findIndex((t) => !t.priority && !t.dismissing);
    if (actionableNonPriorityIdx >= 0) {
      toasts = [
        ...toasts.slice(0, actionableNonPriorityIdx),
        ...toasts.slice(actionableNonPriorityIdx + 1),
      ];
      continue;
    }
    // All remaining are priority (or dismissing) — drop the oldest.
    toasts = toasts.slice(1);
  }
  notify();
  // Auto-dismiss after duration (starts exit animation, not instant
  // removal). The cancel handle is stashed in `dismissTimers` so the
  // hover-pause / resume path can suspend the countdown.
  const cancel = scheduleToastTimer(toastTimerHost, () => dismissToast(id), durationMs);
  dismissTimers.set(id, {
    totalMs: durationMs,
    remainingMs: durationMs,
    startedAt: Date.now(),
    cancel,
  });

  // Keep dedupe map bounded — purge entries older than 4x the longest window.
  const maxWindow = Math.max(...Object.values(DEDUPE_WINDOW_BY_TYPE));
  if (recentToastAt.size > 100) {
    for (const [k, ts] of recentToastAt.entries()) {
      if (now - ts > maxWindow * 4) {
        recentToastAt.delete(k);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Test-only hooks
// ---------------------------------------------------------------------------

/** Test-only: clear the toast stack and dedup map. Exported so unit tests
 *  can start each case with a clean slate without coupling to internals. */
export function __resetToastsForTests(): void {
  for (const state of dismissTimers.values()) state.cancel();
  dismissTimers.clear();
  toasts = [];
  recentToastAt.clear();
  notify();
}

/** Test-only: replace browser timers so store tests do not wait for real auto-dismiss delays. */
export function __setToastTimerHostForTests(host: ToastTimerHost | null): void {
  toastTimerHost = host ?? createBrowserToastTimerHost();
}

/** Test-only: read the current toast list synchronously. Avoids the React
 *  hook path when asserting store state. */
export function __getToastsForTests(): ToastItem[] {
  return [...toasts];
}
