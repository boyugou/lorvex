/**
 * Shared helpers for the one-step undo/redo toast chain on task
 * lifecycle mutations (complete / cancel).
 *
 * The forward mutation (`completeTask` / `cancelTask`) returns a
 * `TaskWithUndo`. The UI shows a success toast with an Undo button
 * bound to the returned `undo_token`. When the user clicks Undo:
 *
 *   1. `undoTaskLifecycle(undo_token)` runs on the backend and restores
 *      the pre-mutation state.
 *   2. The backend returns a `TaskWithRedo` containing a fresh
 *      `redo_token` with a short expiry matching the original undo
 *      hold window.
 *   3. A follow-up info toast fires with a Redo button bound to the
 *      new `redo_token`. Clicking Redo invokes `redoTaskLifecycle`,
 *      which re-runs the original lifecycle mutation through the normal
 *      pipeline and returns a fresh `TaskWithUndo`.
 *   4. That fresh undo token becomes the basis for *another* undo
 *      toast — one more level of back-and-forth, intentionally
 * non-stacking. scope.
 *
 * The chain terminates at depth 2 (undo → redo → undo). If the user
 * undoes the redo, no further redo toast fires — they land back on the
 * ordinary success-toast undo path that would follow any other
 * lifecycle mutation.
 *
 * Scope guards:
 *   - Only task lifecycle (complete/cancel) uses this. `defer` /
 *     `update_task` edits do not get redo affordances.
 *   - No history stack / drawer — the toast chain is the entire UI.
 */
import type { TranslationKey } from '../i18n';
import { redoTaskLifecycle, undoTaskLifecycle } from '@/lib/ipc/tasks/mutations/lifecycle';
import { toast } from '../notifications/toast';
import { reportClientError } from '../errors/errorLogging';
import {
  consumeUndoToken,
  recordUndoToken,
  type RecentUndoAction,
} from '../undoTokenStore';
import {
  buildLifecycleRedoToastAction,
  buildLifecycleUndoToastPlan,
} from './lifecycleUndoRedo.logic';

type Translator = (key: TranslationKey) => string;
type LifecycleDeps = {
  undoTaskLifecycle: typeof undoTaskLifecycle;
  redoTaskLifecycle: typeof redoTaskLifecycle;
  successToast: typeof toast.success;
  infoToast: typeof toast.info;
  errorWithDetailToast: typeof toast.errorWithDetail;
  reportClientError: typeof reportClientError;
  consumeUndoToken: typeof consumeUndoToken;
  recordUndoToken: typeof recordUndoToken;
};

const runtimeDeps: LifecycleDeps = {
  undoTaskLifecycle,
  redoTaskLifecycle,
  successToast: toast.success,
  infoToast: toast.info,
  errorWithDetailToast: toast.errorWithDetail,
  reportClientError,
  consumeUndoToken,
  recordUndoToken,
};

let deps: LifecycleDeps = runtimeDeps;

interface LifecycleUndoRedoOptions {
  /** Called after any successful undo *or* redo mutation so the
   *  caller can invalidate TanStack Query caches bound to the task's
   *  list/view. */
  invalidate: () => void;
  /** Translator for i18n strings. */
  t: Translator;
  /**
   * Error-logging key prefix. The helper appends `.undo` / `.redo`
   * internally so both legs of the chain report under distinct keys.
   */
  errorKeyPrefix: string;
  /**
   * palette-visible undo-token persistence. When supplied, the
   * helper records the token under the given label/action before
   * showing the Undo toast and clears it once the undo actually runs
   * (or expires). Omit for flows that don't surface tokens to the
   * palette.
   */
  persist?: { label: string; action: RecentUndoAction };
}

/**
 * Fire the Undo toast for a freshly-mutated task. Clicking the Undo
 * button runs `undoTaskLifecycle`, then shows a follow-up Redo toast
 * wired to `redoTaskLifecycle` (one-step redo.).
 */
export function showUndoToastWithRedo(
  successMessage: string,
  undoToken: string,
  opts: LifecycleUndoRedoOptions,
): void {
  const plan = buildLifecycleUndoToastPlan(undoToken, opts.t, opts.persist);
  if (plan.persistedEntry) {
    deps.recordUndoToken(plan.persistedEntry);
  }
  const action = plan.action;
  if (!action) {
    deps.successToast(successMessage);
    return;
  }
  deps.successToast(successMessage, {
    label: action.label,
    onClick: () => {
      void runUndoThenOfferRedo(action.token, opts);
    },
  }, action.token);
}

/**
 * Undo-only variant for mutations that don't support a redo step
 * (: `update_task`). Clicking Undo runs `undoTaskLifecycle`,
 * invalidates the caller's caches, and shows a neutral info toast.
 * No follow-up Redo affordance fires — re-applying an arbitrary
 * field patch through a short-lived redo token isn't supported on
 * the backend.
 *
 * An empty `undoToken` (e.g. the backend suppressed the token for a
 * bookkeeping-only patch) renders the success toast without an Undo
 * button rather than surfacing a broken affordance.
 */
export function showUndoOnlyToast(
  successMessage: string,
  undoToken: string,
  opts: LifecycleUndoRedoOptions,
): void {
  const plan = buildLifecycleUndoToastPlan(undoToken, opts.t, opts.persist);
  if (plan.persistedEntry) {
    deps.recordUndoToken(plan.persistedEntry);
  }
  const action = plan.action;
  if (!action) {
    deps.successToast(successMessage);
    return;
  }
  deps.successToast(successMessage, {
    label: action.label,
    onClick: () => {
      void runUndoOnce(action.token, opts);
    },
  }, action.token);
}

/** Internal: run undo for the undo-only flow (no follow-up Redo). */
async function runUndoOnce(
  undoToken: string,
  opts: LifecycleUndoRedoOptions,
): Promise<void> {
  try {
    await deps.undoTaskLifecycle(undoToken);
    deps.consumeUndoToken(undoToken);
    opts.invalidate();
    deps.infoToast(opts.t('task.undone'), undoToken);
  } catch (err) {
    deps.reportClientError(`${opts.errorKeyPrefix}.undo`, 'Failed to undo update mutation', err);
    deps.errorWithDetailToast(err, opts.t('common.error'));
  }
}

/** Internal: run undo, invalidate, then surface the Redo toast. */
async function runUndoThenOfferRedo(
  undoToken: string,
  opts: LifecycleUndoRedoOptions,
): Promise<void> {
  try {
    const result = await deps.undoTaskLifecycle(undoToken);
    deps.consumeUndoToken(undoToken);
    opts.invalidate();
    const redoAction = buildLifecycleRedoToastAction(result.redo_token, opts.t);
    if (!redoAction) {
      deps.infoToast(opts.t('task.undone'), undoToken);
      return;
    }
    // follow-up toast offering a single redo step. Uses info
    // type so it's visually distinct from the green "completed" /
    // "cancelled" forward-mutation toast that preceded it.
    deps.infoToast(opts.t('task.undone'), {
      label: redoAction.label,
      onClick: () => {
        void runRedoThenOfferUndo(redoAction.token, opts);
      },
    }, redoAction.token);
  } catch (err) {
    deps.reportClientError(`${opts.errorKeyPrefix}.undo`, 'Failed to undo lifecycle mutation', err);
    deps.errorWithDetailToast(err, opts.t('common.error'));
  }
}

/**
 * Internal: run redo, invalidate, then surface a fresh Undo toast.
 * The chain terminates here — clicking Undo on this new toast runs
 * `undoTaskLifecycle` and does NOT re-offer Redo, because scope
 * explicitly caps the chain at one step (undo → redo → undo, no more).
 * That terminal Undo is fulfilled by calling back into this module's
 * plain `undoTaskLifecycle` wrapper without re-entering the chain.
 */
async function runRedoThenOfferUndo(
  redoToken: string,
  opts: LifecycleUndoRedoOptions,
): Promise<void> {
  try {
    const result = await deps.redoTaskLifecycle(redoToken);
    opts.invalidate();
    const undoPlan = buildLifecycleUndoToastPlan(result.undo_token, opts.t, opts.persist);
    if (undoPlan.persistedEntry) {
      deps.recordUndoToken(undoPlan.persistedEntry);
    }
    const action = undoPlan.action;
    if (!action) {
      deps.successToast(opts.t('task.redone'), redoToken);
      return;
    }
    deps.successToast(opts.t('task.redone'), {
      label: action.label,
      onClick: () => {
        void terminalUndo(action.token, opts);
      },
    }, action.token);
  } catch (err) {
    deps.reportClientError(`${opts.errorKeyPrefix}.redo`, 'Failed to redo lifecycle mutation', err);
    deps.errorWithDetailToast(err, opts.t('common.error'));
  }
}

/** Terminal leg of the chain: undo of a redo. No further Redo
 *  affordance fires — one level only. */
async function terminalUndo(
  undoToken: string,
  opts: LifecycleUndoRedoOptions,
): Promise<void> {
  try {
    await deps.undoTaskLifecycle(undoToken);
    deps.consumeUndoToken(undoToken);
    opts.invalidate();
    deps.infoToast(opts.t('task.undone'), undoToken);
  } catch (err) {
    deps.reportClientError(
      `${opts.errorKeyPrefix}.undoOfRedo`,
      'Failed to undo redone lifecycle mutation',
      err,
    );
    deps.errorWithDetailToast(err, opts.t('common.error'));
  }
}

export const __TEST_ONLY__ = {
  setDepsForTests(overrides: Partial<LifecycleDeps>): void {
    deps = {
      ...runtimeDeps,
      ...overrides,
    };
  },
  resetDepsForTests(): void {
    deps = runtimeDeps;
  },
};
