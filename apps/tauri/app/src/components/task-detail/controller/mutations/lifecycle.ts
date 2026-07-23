import { useCallback } from 'react';
import { deferTask, deferTaskUntil, resetTaskDeferral } from '@/lib/ipc/tasks/mutations/deferral';
import { archiveTask, cancelTask, completeTask, reopenTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { duplicateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { DEFER_REASON_NOT_TODAY, TASK_STATUS } from '@lorvex/shared/types';
import { confirm } from '@/lib/dialogs/confirm';
import { runTaskDeferralWithUndo } from '@/lib/tasks/deferralUndo';
import { showUndoToastWithRedo } from '@/lib/tasks/lifecycleUndoRedo';
import { toast } from '@/lib/notifications/toast';
import { normalizeDeferDate, reportTaskDetailActionError } from '@/components/task-detail/support';
import type { UseTaskDetailLifecycleMutationDeps } from './types';

export function useTaskDetailLifecycleMutations({
  invalidateAll,
  isCompleting,
  mountedRef,
  onClose,
  persistDraftsRef,
  setIsCompleting,
  task,
  format,
  t,
}: UseTaskDetailLifecycleMutationDeps) {
  const handleComplete = useCallback(async () => {
    if (!task || task.status === TASK_STATUS.completed || isCompleting) return;
    const ok = await persistDraftsRef.current();
    if (!ok || !mountedRef.current) return;
    setIsCompleting(true);
    try {
      const result = await completeTask(task.id);
      invalidateAll();
      showUndoToastWithRedo(format('task.status.completedNamed', { title: task.title }), result.undo_token, {
        invalidate: invalidateAll,
        t,
        errorKeyPrefix: 'taskDetail.complete',
      });
    } catch (taskError) {
      reportTaskDetailActionError('complete', taskError, task.id);
      toast.errorWithDetail(taskError, t('common.error'));
    } finally {
      if (mountedRef.current) {
        setIsCompleting(false);
      }
    }
  }, [format, invalidateAll, isCompleting, mountedRef, persistDraftsRef, setIsCompleting, t, task]);

  const handleDefer = useCallback(async (untilDate: string | null, onSettled?: () => void) => {
    if (!task) return;
    const ok = await persistDraftsRef.current();
    if (!ok || !mountedRef.current) return;
    await runTaskDeferralWithUndo({
      task,
      runDefer: () => untilDate
        ? deferTaskUntil(task.id, normalizeDeferDate(untilDate), DEFER_REASON_NOT_TODAY)
        : deferTask(task.id, DEFER_REASON_NOT_TODAY),
      invalidate: invalidateAll,
      afterForwardSuccess: onSettled,
      successMessage: t('task.deferred'),
      undoLabel: t('common.undo'),
      undoSuccessMessage: t('task.undone'),
      reportForwardError: (taskError) => reportTaskDetailActionError('defer', taskError, task.id),
      forwardErrorSource: 'taskDetail.defer',
      forwardErrorMessage: 'Failed to defer task',
      forwardErrorDetails: task.id,
      forwardErrorToastMessage: t('common.error'),
      reportUndoError: (undoError) => reportTaskDetailActionError('undo-defer', undoError, task.id),
      undoErrorSource: 'taskDetail.undo-defer',
      undoErrorMessage: 'Failed to undo defer',
      undoErrorDetails: task.id,
      undoErrorToastMessage: t('common.error'),
    });
  }, [invalidateAll, mountedRef, persistDraftsRef, t, task]);

  const handleReopen = useCallback(async () => {
    if (!task) return;
    try {
      const ok = await persistDraftsRef.current();
      if (!ok || !mountedRef.current) return;
      await reopenTask(task.id);
      if (!mountedRef.current) return;
      invalidateAll();
      toast.success(t('task.reopen'));
    } catch (taskError) {
      reportTaskDetailActionError('reopen', taskError, task.id);
      toast.errorWithDetail(taskError, t('common.error'));
    }
  }, [invalidateAll, mountedRef, persistDraftsRef, t, task]);

  const handleDelete = useCallback(async (cancelSeries?: boolean) => {
    if (!task) return;
    // cancelling the entire recurrence series wipes every
    // future occurrence. Gate with a confirm so an accidental
    // misclick on "Cancel series" doesn't silently destroy the
    // schedule. Single-occurrence cancel still routes through the
    // standard Undo toast.
    if (cancelSeries) {
      const ok = await confirm({
        title: t('task.cancelSeriesConfirmTitle'),
        message: t('task.cancelSeriesConfirmMessage'),
        variant: 'danger',
        confirmLabel: t('task.cancelSeriesConfirmAction'),
      });
      if (!ok) return;
    }
    try {
      const ok = await persistDraftsRef.current();
      if (!ok) return;
      const result = await cancelTask(task.id, cancelSeries);
      invalidateAll();
      onClose();
      showUndoToastWithRedo(t('task.status.cancelled'), result.undo_token, {
        invalidate: invalidateAll,
        t,
        errorKeyPrefix: 'taskDetail.cancel',
      });
    } catch (taskError) {
      reportTaskDetailActionError('cancel', taskError, task.id);
      toast.errorWithDetail(taskError, t('common.error'));
    }
  }, [invalidateAll, onClose, persistDraftsRef, t, task]);

  const handlePermanentDelete = useCallback(async () => {
    if (!task) return;
    // "Delete forever" from the task-detail header now
    // routes through the Trash so the user has 30 days of undo. The
    // old `permanent_delete_task` path rejects non-archived tasks and
    // is only invoked from the Trash view's per-row action.
    const ok = await confirm({
      title: t('task.move_to_trash'),
      message: t('task.confirmPermanentDelete'),
      confirmLabel: t('task.move_to_trash'),
      variant: 'danger',
    });
    if (!ok) return;
    try {
      const draftsOk = await persistDraftsRef.current();
      if (!draftsOk) return;
      await archiveTask(task.id);
      invalidateAll();
      onClose();
      toast.success(t('task.deleteSuccess'));
    } catch (taskError) {
      reportTaskDetailActionError('archive', taskError, task.id);
      toast.errorWithDetail(taskError, t('common.error'));
    }
  }, [invalidateAll, onClose, persistDraftsRef, t, task]);

  const handleResetDeferral = useCallback(async () => {
    if (!task) return;
    try {
      const ok = await persistDraftsRef.current();
      if (!ok) return;
      await resetTaskDeferral(task.id);
      invalidateAll();
    } catch (taskError) {
      reportTaskDetailActionError('reset-deferral', taskError, task.id);
      toast.errorWithDetail(taskError, t('common.error'));
    }
  }, [invalidateAll, persistDraftsRef, t, task]);

  const handleDuplicate = useCallback(async () => {
    if (!task) return;
    try {
      const ok = await persistDraftsRef.current();
      if (!ok) return;
      const cloned = await duplicateTask(task.id);
      invalidateAll();
      toast.success(format('task.duplicatedNamed', { title: cloned.title }));
    } catch (taskError) {
      reportTaskDetailActionError('duplicate', taskError, task.id);
      toast.errorWithDetail(taskError, t('common.error'));
    }
  }, [format, invalidateAll, persistDraftsRef, t, task]);

  return {
    handleComplete,
    handleDelete,
    handleDuplicate,
    handlePermanentDelete,
    handleReopen,
    handleResetDeferral,
    handleDefer,
  };
}
