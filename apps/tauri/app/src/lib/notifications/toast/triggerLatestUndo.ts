/**
 * Global ⌘Z/Ctrl+Z entry point: invoke the action of the most-recent
 * actionable toast that is still visible.
 *
 * Errors thrown synchronously by the action and rejections from any
 * Promise it returns are routed to `reportClientError` so undo
 * regressions surface in the client error log. The user-facing failure
 * message is owned by the action itself (see `runUndoThenOfferRedo`,
 * which routes errors through `toast.errorWithDetail`); we deliberately
 * do not double-emit a generic toast here, which would risk shadowing
 * the more specific message the action surfaces.
 */

import { reportClientError } from '../../errors/errorLogging';
import { dismissToast, findLatestActionableToast } from './store';

/**
 * Invoke the action of the most-recent actionable toast that is still
 * visible (not already dismissing). Returns true if an action fired.
 * Used by the global ⌘Z/Ctrl+Z keyboard shortcut so power users can
 * trigger the undo-toast without reaching for the mouse.
 */
export function triggerLatestUndo(): boolean {
  const target = findLatestActionableToast();
  if (!target || !target.action) return false;
  const action = target.action;
  dismissToast(target.id);
  try {
    const result = action.onClick();
    if (result && typeof (result as Promise<unknown>).catch === 'function') {
      void (result as Promise<unknown>).catch((err) => {
        reportClientError(
          'toast.triggerLatestUndo',
          'Undo action rejected (keyboard shortcut path)',
          err,
          undefined,
          'warn',
        );
      });
    }
  } catch (err) {
    reportClientError(
      'toast.triggerLatestUndo',
      'Undo action threw (keyboard shortcut path)',
      err,
    );
  }
  return true;
}
