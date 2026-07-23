/**
 * Shared toast value types.
 *
 * The four-channel toast surface (`success`/`error`/`warning`/`info`) is built
 * around a single `ToastItem` value carrying an optional action button, an
 * optional dedup discriminator, a priority flag (for coalesced bulk-undo
 * affordances that must survive `MAX_TOASTS` eviction), and a total
 * auto-dismiss duration the renderer uses to size the progress bar.
 */

export type ToastType = 'success' | 'error' | 'info' | 'warning';

export interface ToastAction {
  label: string;
  // Return type is `void | Promise<void>` so an async `onClick`
  // (e.g. `async () => { await runUndo(...) }`) declares its
  // asynchronous completion at the type level. A bare `() => void`
  // would let TS implicitly accept async callbacks (`Promise<void>`
  // is assignable to `void` in callback positions) and the resulting
  // Promise rejection would slip past the renderer's `try/catch`.
  onClick: () => void | Promise<void>;
}

export interface ToastItem {
  id: string;
  message: string;
  type: ToastType;
  action?: ToastAction | undefined;
  context?: string | undefined;
  /** When true, the toast is in its CSS exit animation and will be removed
   *  from the DOM when the transition completes (via transitionend). */
  dismissing?: boolean | undefined;
  /** Priority toasts (e.g. a coalesced bulk-undo carrying a single undo
   *  token for N tasks) are protected from MAX_TOASTS eviction: when the
   *  stack overflows, we evict non-priority toasts first, even if they
   *  carry a (single-item) action. */
  priority?: boolean | undefined;
  /** Total auto-dismiss duration in ms. Used by the renderer to size
   *  the progress bar; the actual dismiss timer is owned by the
   *  module-level scheduler. */
  durationMs?: number | undefined;
}

/** Options for toasts that carry an action button. */
export interface ToastActionableOptions {
  /** Override the default actionable-toast duration. Useful for bulk
   *  operations where visibility should scale with the magnitude of
   *  the action — 20 completions deserve a longer window than 1. */
  durationMs?: number;
  /** Mark as a priority toast that survives MAX_TOASTS eviction. Used
   *  for coalesced bulk-undo affordances where losing the toast means
   *  losing the only undo path for dozens of tasks. */
  priority?: boolean;
  /** Optional dedup discriminator. */
  context?: string;
}

export type ToastListener = (toasts: ToastItem[]) => void;
