/**
 * Per-type toast display durations, the matching dedup windows, and the
 * length-scaling helper for actionable toasts.
 *
 * Each dedup window is tied to the toast's actual on-screen display
 * duration so a duplicate cannot slip past the dedup AND stack on top
 * of the still-visible original. A window shorter than the display
 * duration would leave a gap (e.g. a 3000ms window on a 4000ms-visible
 * error toast) in which a duplicate fires between the window expiry
 * and the on-screen dismissal, briefly showing two identical toasts.
 * Matching the window to the display duration closes that gap; once a
 * duplicate arrives, the original is guaranteed to either be dismissing
 * or already removed. Success uses the `SUCCESS_TOAST_DURATION_MS`
 * (2500ms) for the same reason — a shorter (1000ms) window would let
 * rapid double-clicks double-stack the same "Task completed" message.
 */

import type { ToastType } from './types';

export const MAX_TOASTS = 5;

/** Duration of the CSS exit transition — must match the toast-enter-exit
 *  utility timing in index.css. Used as a fallback in case transitionend
 *  never fires (e.g. element removed during animation). */
export const EXIT_TRANSITION_MS = 220;

export const SUCCESS_TOAST_DURATION_MS = 2500;
// Must be shorter than the backend undo hold (5s) to prevent users clicking
// the undo button after the backend token has expired. The 220ms exit
// animation means the button is visually present for duration + 220ms.
export const ACTIONABLE_SUCCESS_TOAST_DURATION_MS = 4500;
export const ERROR_TOAST_DURATION_MS = 4000;
export const INFO_TOAST_DURATION_MS = 3000;
export const ACTIONABLE_INFO_TOAST_DURATION_MS = 5000;
// warning sits between info and error — users have to take an
// action (e.g. manually clean up an orphan), but the operation itself
// did not fully fail. Match the error display duration so the copy has
// time to be read; visually distinct via a yellow/amber tint.
export const WARNING_TOAST_DURATION_MS = 4500;

/** Dedup windows per toast type. Bound to the display durations above so
 *  a repeat firing of the same key cannot land while the original is
 *  still on screen. See the module docstring for the gap-closing
 *  rationale. */
export const DEDUPE_WINDOW_BY_TYPE: Record<ToastType, number> = {
  // Bind dedup windows to the display durations. The
  // error/info window jumps to the non-actionable duration plus the
  // 220ms exit transition, rounded up to a clean ceiling; success
  // matches its own display duration.
  error: ERROR_TOAST_DURATION_MS + EXIT_TRANSITION_MS + 280, // = 4500
  info: INFO_TOAST_DURATION_MS + EXIT_TRANSITION_MS + 480, // = 3700; safer ceiling for actionable info
  success: SUCCESS_TOAST_DURATION_MS,
  warning: WARNING_TOAST_DURATION_MS + EXIT_TRANSITION_MS + 280, // = 5000
};

// long messages need more dwell time. The original 4500ms
// success-undo window assumed short copy ("Task completed") but bulk
// operations now produce messages like
// "Moved 12 tasks from Today to Inbox — Undo".
// Heuristic: scale duration by message length above ~40 chars (~30ms per
// extra character). The success path is capped to stay under the backend
// undo hold (5000ms) — the toast must dismiss before the token expires so
// users don't tap a dead button. Error/info actionables have no backend
// timeout and use a higher ceiling.
const ACTIONABLE_DURATION_LENGTH_THRESHOLD = 40;
const ACTIONABLE_DURATION_PER_EXTRA_CHAR_MS = 30;
// raise the success-actionable cap above the backend's 5000ms
// undo hold so a long, length-scaled toast can still display its full
// scaled duration (was 4900ms which rounded long messages back down to
// just under the hold). 5500ms keeps the Undo button visible past the
// backend expiry by ~500ms; clicking expired tokens already surfaces a
// clean error path through `toast.errorWithDetail`, so the brief
// overhang is preferable to silently truncating long copy.
export const MAX_SUCCESS_ACTIONABLE_DURATION_MS = 5500;
export const MAX_NON_SUCCESS_ACTIONABLE_DURATION_MS = 8000;

/** Length-scale a base actionable duration so long copy stays readable
 *  before the action button disappears. Returns `baseMs` unchanged for
 *  short messages; caps at `capMs` for very long ones. */
export function scaleActionableDuration(baseMs: number, message: string, capMs: number): number {
  const overflow = message.length - ACTIONABLE_DURATION_LENGTH_THRESHOLD;
  if (overflow <= 0) return baseMs;
  const scaled = baseMs + overflow * ACTIONABLE_DURATION_PER_EXTRA_CHAR_MS;
  return Math.min(scaled, capMs);
}
