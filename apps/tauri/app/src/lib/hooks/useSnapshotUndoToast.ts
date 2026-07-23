/**
 * Shared snapshot-undo toast affordance.
 *
 * Multiple delete-with-undo flows (calendar events, lists) all share an
 * identical shape: the backend returns an opaque `undo_token` that, when
 * fed back through `undoDeleteEntity`, replays a pre-delete snapshot
 * within a short TTL (~5s). The UI surfaces this as a success toast with
 * an "Undo" action button; clicking it within the TTL invokes the undo
 * IPC, invalidates the relevant caches, and announces the restoration.
 *
 * Pre-extraction this block was duplicated three times (sidebar list
 * delete, day-panel event delete, event-form delete) and one of those
 * copies pasted the wrong-domain `calendar.undoExpired` key into a
 * list-domain failure path. Centralising the dispatch — and
 * making each call site declare its own `expiredKey` / `restoredKey` —
 * structurally prevents the cross-domain key copy/paste from recurring.
 *
 * The hook also offers `onAfterUndoExpired`: a callback that
 * runs only when the undo window passes WITHOUT the user clicking
 * Undo. List delete uses this to defer "navigate away from the
 * now-deleted list" until the restore window has closed — otherwise a
 * successful Undo would land the user on Today instead of the list
 * they restored.
 */
import { useCallback } from 'react';
import { useQueryClient, type QueryClient } from '@tanstack/react-query';

import { useI18n, type TranslationKey } from '../i18n';
import { undoDeleteEntity } from '@/lib/ipc/snapshotUndo';
import { reportClientError } from '../errors/errorLogging';
import { toast } from '../notifications/toast';

/**
 * Domain that owns this snapshot-undo affordance. Currently used as the
 * `errorLogging` surface key (`undo-delete:<kind>`) so the two delete
 * flows surface distinct error keys, and to mark the toast `context`
 * for dedup. Extend the union when a new entity gains snapshot-undo.
 */
type SnapshotUndoKind = 'list' | 'calendar_event';

interface SnapshotUndoConfig {
  /** Domain marker for logging + toast dedup. */
  kind: SnapshotUndoKind;
  /** Opaque token returned by the delete IPC; consumed by `undoDeleteEntity`. */
  token: string;
  /** Translation key for the "[X] deleted" success message that owns the
   *  Undo button. (e.g. `calendar.eventDeleted`, `list.deleteSuccess`.) */
  successKey: TranslationKey;
  /** Translation key for the Undo button label. Defaults to `common.undo`
   *  for every caller today; exposed for parity with future variants. */
  undoLabelKey?: TranslationKey;
  /** Translation key for the info toast shown on successful restore.
   *  (e.g. `calendar.eventRestored`, `list.restored`.) */
  restoredKey: TranslationKey;
  /** Translation key for the error toast when the undo IPC fails — most
   *  commonly because the undo window expired. Defaults to the generic
   * `undo.expired`. */
  expiredKey?: TranslationKey;
  /** Cache invalidator. Runs on successful undo to repopulate every
   *  surface that displayed the now-restored row. */
  invalidate: (qc: QueryClient) => void;
  /** Optional callback fired ONLY when the undo TTL passes without the
   * user clicking Undo. Used by list delete to defer
   *  "navigate away" until after the user has had a chance to undo —
   *  otherwise the restored list would still leave the user stranded
   *  on the Today view. */
  onAfterUndoExpired?: () => void;
  /** Optional callback fired AFTER a successful snapshot restore but
   *  before the user-facing "[X] restored" info toast. Used by
   * compound-undo flows to clean up sibling rows the
   *  destructive op spawned alongside the snapshot — e.g. the
   *  thisAndFollowing edit creates a replacement series before
   *  deleting the original; on Undo we restore the original AND must
   *  delete the replacement, otherwise the user is left with two
   *  overlapping series.
   *
   *  The callback receives the same `QueryClient` as `invalidate`. It
   *  is awaited; throwing surfaces the error through the same
   *  `reportClientError` channel the IPC failure path uses, but does
   *  NOT roll back the restore (the snapshot is already back). */
  onAfterUndo?: (qc: QueryClient) => void | Promise<void>;
}

/**
 * Approximate ceiling on the undo TTL the user is offered. Slightly
 * longer than the toast's actionable display duration so the deferred
 * `onAfterUndoExpired` only fires after the toast has visibly
 * disappeared. The backend hold is 5s; we add a small grace window
 * before treating undo as missed to absorb scheduler jitter.
 */
const UNDO_EXPIRY_GRACE_MS = 6000;

type ShowSnapshotUndoToast = (config: SnapshotUndoConfig) => void;

/**
 * React hook that returns a stable function to surface a snapshot-undo
 * toast for a delete operation. The returned `show` is callback-stable
 * across renders (depends only on i18n + queryClient).
 */
export function useSnapshotUndoToast(): ShowSnapshotUndoToast {
  const { t } = useI18n();
  const qc = useQueryClient();

  return useCallback<ShowSnapshotUndoToast>(
    (config) => {
      const expiredKey: TranslationKey = config.expiredKey ?? 'undo.expired';
      const undoLabelKey: TranslationKey = config.undoLabelKey ?? 'common.undo';
      let undoSucceeded = false;
      // Always arm the expiry timer, even when no callback is
      // supplied. Two concrete reasons:
      //   1. The `undoSucceeded` latch is observable in tests
      //      regardless of caller config, keeping the lifecycle
      //      simple.
      //   2. The same timer drives a deterministic cleanup path
      //      even when no caller-supplied callback exists — there
      //      is no leaked `setTimeout` either way.
      // The timer's job is "fire `onAfterUndoExpired` once if and
      // only if the undo did NOT succeed within the grace window".
      const expiryTimer = setTimeout(() => {
        if (!undoSucceeded) config.onAfterUndoExpired?.();
      }, UNDO_EXPIRY_GRACE_MS);
      toast.success(
        t(config.successKey),
        {
          label: t(undoLabelKey),
          onClick: async () => {
            // handle the IPC inline so the click can
            //   * keep the toast button alive while the request is
            //     in flight (the container shows a spinner via the
            //     promise it received here);
            //   * fire `onAfterUndoExpired` when the IPC rejects.
            //
            // Contract: only suppress the deferred callback when
            // the row was actually restored. A click that bounced
            // (expired-window race, FK conflict, etc.) is
            // indistinguishable from no click at all in terms of
            // the state the user is left looking at, so
            // `onAfterUndoExpired` still runs to navigate them
            // somewhere sensible — alongside the error toast that
            // explains what happened.
            try {
              await undoDeleteEntity(config.token);
              undoSucceeded = true;
              clearTimeout(expiryTimer);
              config.invalidate(qc);
              // compound-undo hook. Runs AFTER the restore is
              // confirmed but before the user-facing info toast so any
              // sibling cleanup (e.g. delete the replacement series
              // the original destructive op created) lands before the
              // user navigates away. Failures are reported but do not
              // roll back — the restore already succeeded.
              let afterUndoFailed = false;
              if (config.onAfterUndo) {
                try {
                  await config.onAfterUndo(qc);
                } catch (afterErr) {
                  afterUndoFailed = true;
                  reportClientError(
                    `undo-delete:${config.kind}`,
                    'Snapshot undo onAfterUndo failed',
                    afterErr,
                  );
                }
              }
              if (afterUndoFailed) {
                // the snapshot was restored successfully, but
                // the compound-undo cleanup (e.g. delete the
                // just-created replacement series) failed. Surface the
                // partial-failure to the user as a warning instead of
                // staying silent — they now have BOTH the restored
                // original AND the orphaned replacement, and need to
                // know about the second one. Suppress the success
                // toast so the warning is the only message they see;
                // the warning itself acknowledges that the restore
                // happened.
                // route through the dedicated `warning` channel.
                // `error` was a poor fit — the snapshot restore SUCCEEDED;
                // only the compound cleanup failed, and the user needs
                // to take a manual cleanup step rather than treat the
                // whole undo as broken. The amber-tinted toast reads as
                // "attention required" without escalating to total
                // failure.
                toast.warning(t('undo.replacementCleanupFailed'));
              } else {
                toast.info(t(config.restoredKey));
              }
            } catch (err) {
              reportClientError(`undo-delete:${config.kind}`, 'Snapshot undo failed', err);
              toast.error(t(expiredKey));
              // Fire the deferred callback now (don't wait for the
              // grace window) so the user navigates away as soon as
              // we know the undo failed. Cancel the timer so the
              // callback can't double-fire.
              clearTimeout(expiryTimer);
              if (!undoSucceeded) config.onAfterUndoExpired?.();
            }
          },
        },
        config.token,
      );
    },
    [qc, t],
  );
}
