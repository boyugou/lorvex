/**
 * Pure routing helpers for ToastContainer.
 *
 * Live-region routing splits visible toasts into two announcement
 * lanes — `assertive` for outcomes the user must hear right now, and
 * `polite` for confirmations that can wait until AT speech is idle.
 *
 *   - `error`   — total failure. Always assertive.
 * - `warning` — partial-failure outcomes the user must
 *                 address. Assertive: routing them to polite buried
 *                 the message behind any in-flight speech and the user
 *                 missed the failure mid-stream.
 *   - `success` — confirmation of an action that worked. Polite.
 *   - `info`    — passive notice. Polite.
 *
 * Extracted from the inline filter callbacks in `ToastContainer.tsx`
 * so the routing rule has a single source of truth and is unit-testable
 * without rendering React.
 */
import type { ToastItem } from '../lib/notifications/toast';

/**
 * Decide which live-region lane a toast announces through.
 *
 * The component-level visual stack split (priority lane vs. ambient
 * lane) reuses this same predicate so the visual and aural priority
 * tiers stay in lock-step — a toast that announces assertively also
 * stacks with errors, never with the ambient success/info lane.
 */
export function isAssertiveToast(t: Pick<ToastItem, 'type'>): boolean {
  return t.type === 'error' || t.type === 'warning';
}
