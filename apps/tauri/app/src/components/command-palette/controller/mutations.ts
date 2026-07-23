import { useCallback, type Dispatch, type SetStateAction } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { DEFER_REASON_NOT_TODAY } from '@lorvex/shared/types';
import { createList, deleteList, shelveList as shelveListIpc } from '@/lib/ipc/tasks/lists';
import type { Task } from '@/lib/ipc/tasks/models';
import { deferTask } from '@/lib/ipc/tasks/mutations/deferral';
import { cancelTask, completeTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import type { TaskWithUndo } from '@/lib/ipc/tasks/mutations/types';
import { confirm } from '@/lib/dialogs/confirm';
import { reportClientError } from '@/lib/errors/errorLogging';
import { invalidateListQueries, invalidateTaskMutationQueries } from '@/lib/query/queryKeys';
import { runTaskDeferralWithUndo } from '@/lib/tasks/deferralUndo';
import { showUndoToastWithRedo } from '@/lib/tasks/lifecycleUndoRedo';
import { toast } from '@/lib/notifications/toast';
import type { RecentUndoAction } from '@/lib/undoTokenStore';
import type { TranslationKey, TranslationVars } from '@/locales';

export type PaletteMutationRunner = (
  execute: () => Promise<unknown>,
  logLabel: string,
  options?: { affectedListIds?: Array<string | null | undefined> },
) => void;

interface UsePaletteMutationActionsArgs {
  confirmArchiveListId: string | null;
  onClose: () => void;
  query: string;
  setConfirmArchiveListId: Dispatch<SetStateAction<string | null>>;
  t: (key: TranslationKey) => string;
  format: (key: TranslationKey, vars?: TranslationVars) => string;
}

export function usePaletteMutationActions({
  confirmArchiveListId,
  onClose,
  query,
  setConfirmArchiveListId,
  t,
  format,
}: UsePaletteMutationActionsArgs): {
  shelveListFromPalette: (listId: string, listName: string) => void;
  cancelFromPalette: (task: Task) => void;
  completeFromPalette: (task: Task) => void;
  createListFromPalette: (name: string) => void;
  deferFromPalette: (task: Task) => void;
  deleteListFromPalette: (listId: string) => void;
  runPaletteMutation: PaletteMutationRunner;
} {
  const qc = useQueryClient();

  const invalidateAfterWrite = useCallback(() => {
    invalidateTaskMutationQueries(qc);
  }, [qc]);

  const reportPaletteError = useCallback(
    (action: string, error: unknown) => {
      reportClientError(
        `commandPalette.${action}`,
        `Palette action failed: ${action}`,
        error,
        query,
        'warn',
      );
    },
    [query],
  );

  const runPaletteMutation = useCallback<PaletteMutationRunner>(
    (execute, logLabel, options) => {
      void execute()
        .then(() => {
          invalidateAfterWrite();
          for (const listId of options?.affectedListIds ?? []) {
            if (listId === null || listId === undefined) continue;
            invalidateListQueries(qc, listId);
          }
          onClose();
        })
        .catch((error) => {
          reportPaletteError(logLabel, error);
          toast.errorWithDetail(error, t('common.error'));
        });
    },
    [invalidateAfterWrite, onClose, qc, reportPaletteError, t],
  );

  /** Run a task status mutation with undo. Only shows undo button when the action returns an undo_token (complete/cancel). */
  const runUndoableTaskMutation = useCallback(
    (
      action: (taskId: string) => Promise<TaskWithUndo | Task>,
      task: Task,
      logLabel: string,
      namedMessageKey: TranslationKey,
      toastFn: typeof toast.success,
      recentAction: RecentUndoAction,
    ) => {
      void action(task.id)
        .then((result) => {
          const undoToken = result && typeof result === 'object' && 'undo_token' in result
            ? (result as TaskWithUndo).undo_token
            : null;
          invalidateAfterWrite();
          onClose();
          const message = format(namedMessageKey, { title: task.title });
          if (undoToken) {
            // the helper records the token via
            // `persist` so the palette's "Recent actions → Undo" group
            // can still redeem it if the toast is evicted by
            // navigation / Focus Mode / reload inside the 5s backend
            // hold; the helper also offers a one-step Redo after Undo.
            showUndoToastWithRedo(message, undoToken, {
              invalidate: invalidateAfterWrite,
              t,
              errorKeyPrefix: `commandPalette.${logLabel}`,
              persist: { label: message, action: recentAction },
            });
          } else {
            toastFn(message);
          }
        })
        .catch((error) => {
          reportPaletteError(logLabel, error);
          toast.errorWithDetail(error, t('common.error'));
        });
    },
    [format, invalidateAfterWrite, onClose, reportPaletteError, t],
  );

  const shelveListFromPalette = useCallback(
    (listId: string, listName: string) => {
      const armed = confirmArchiveListId === listId;
      if (!armed) {
        setConfirmArchiveListId(listId);
        return;
      }

      setConfirmArchiveListId(null);
      void shelveListIpc(listId)
        .then((result) => {
          if (result.shelved_count === 0) {
            toast.info(t('review.noActiveTasks'));
            return;
          }
          invalidateAfterWrite();
          invalidateListQueries(qc, listId);
          onClose();
          toast.success(format('review.shelvedToSomedayNamed', { list: listName }));
          // Surface the LWW-rejected / concurrently-mutated rows so
          // the user knows the operation didn't land for every open
          // task — those rows reconverge on the next sync apply tick.
          if (result.skipped_task_ids.length > 0) {
            toast.info(format('review.shelveSkipped', { count: result.skipped_task_ids.length }));
          }
        })
        .catch((error) => {
          reportPaletteError('shelve-list', error);
          toast.errorWithDetail(error, t('common.error'));
        });
    },
    [confirmArchiveListId, format, invalidateAfterWrite, onClose, qc, reportPaletteError, setConfirmArchiveListId, t],
  );

  // delete-list in the command palette used an inline
  // two-click arming pattern ("Delete list" → "Confirm delete list"
  // on a second Enter) that was inconsistent with every other
  // destructive delete in the app, which all route through the
  // shared confirm() modal. A user with an armed delete + a stray
  // Enter keystroke could nuke a list silently. Swap to the same
  // confirm() modal used by the sidebar context menu, list-view
  // header, task permanent-delete, calendar event delete, and AI
  // memory forget flows.
  const deleteListFromPalette = useCallback(
    (listId: string) => {
      setConfirmArchiveListId(null);
      void confirm({
        title: t('palette.deleteList'),
        message: t('list.deleteConfirm'),
        variant: 'danger',
        confirmLabel: t('palette.deleteList'),
      }).then((confirmed) => {
        if (!confirmed) return;
        void deleteList(listId)
          .then(() => {
            invalidateAfterWrite();
            invalidateListQueries(qc, listId);
            onClose();
          })
          .catch((error) => {
            reportPaletteError('delete-list', error);
            toast.errorWithDetail(error, t('common.error'));
          });
      });
    },
    [invalidateAfterWrite, onClose, qc, reportPaletteError, setConfirmArchiveListId, t],
  );

  const completeFromPalette = useCallback(
    (task: Task) => runUndoableTaskMutation(completeTask, task, 'complete', 'task.status.completedNamed', toast.success, 'complete'),
    [runUndoableTaskMutation],
  );

  const deferFromPalette = useCallback(
    (task: Task) => {
      void runTaskDeferralWithUndo({
        task,
        runDefer: () => deferTask(task.id, DEFER_REASON_NOT_TODAY),
        invalidate: invalidateAfterWrite,
        afterForwardSuccess: onClose,
        successMessage: format('task.deferredNamed', { title: task.title }),
        successToast: toast.info,
        undoLabel: t('common.undo'),
        undoSuccessMessage: t('task.undone'),
        reportForwardError: (error) => reportPaletteError('defer', error),
        forwardErrorSource: 'commandPalette.defer',
        forwardErrorMessage: 'Palette action failed: defer',
        forwardErrorDetails: query,
        forwardErrorLevel: 'warn',
        forwardErrorToastMessage: t('common.error'),
        reportUndoError: (error) => reportPaletteError('defer-undo', error),
        undoErrorSource: 'commandPalette.defer-undo',
        undoErrorMessage: 'Palette action failed: defer-undo',
        undoErrorDetails: query,
        undoErrorLevel: 'warn',
        undoErrorToastMessage: t('common.error'),
      });
    },
    [format, invalidateAfterWrite, onClose, query, reportPaletteError, t],
  );

  const cancelFromPalette = useCallback(
    (task: Task) => runUndoableTaskMutation(cancelTask, task, 'cancel', 'task.status.cancelledNamed', toast.info, 'cancel'),
    [runUndoableTaskMutation],
  );

  const createListFromPalette = useCallback(
    (name: string) => {
      runPaletteMutation(
        () => createList({ name }),
        'create-list',
      );
    },
    [runPaletteMutation],
  );

  return {
    shelveListFromPalette,
    cancelFromPalette,
    completeFromPalette,
    createListFromPalette,
    deferFromPalette,
    deleteListFromPalette,
    runPaletteMutation,
  };
}
