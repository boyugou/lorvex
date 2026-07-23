import { useCallback, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { getNextMondayYmd } from '@/lib/dayContextMath';
import { useDayContext } from '@/lib/DayContextProvider';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import type { Task } from '@/lib/ipc/tasks/models';
import { deferTaskUntil } from '@/lib/ipc/tasks/mutations/deferral';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { isTaskActive } from '@/lib/format';
import { invalidateTaskMutationQueries } from '@/lib/query/queryKeys';
import { runTaskDeferralWithUndo } from '@/lib/tasks/deferralUndo';
import { toast } from '@/lib/notifications/toast';
import { DEFER_REASON_NOT_TODAY, TASK_STATUS } from '@lorvex/shared/types';

export function useTaskCardQuickActionHandlers(task: Task) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const dayContext = useDayContext();
  const [actionPending, setActionPending] = useState(false);

  const invalidateTask = useCallback(() => {
    invalidateTaskMutationQueries(queryClient, { listId: task.list_id });
  }, [queryClient, task.list_id]);

  const handleDeferTomorrow = useCallback(async () => {
    if (actionPending) return;
    setActionPending(true);
    try {
      await runTaskDeferralWithUndo({
        task,
        runDefer: () => deferTaskUntil(task.id, dayContext.tomorrowYmd, DEFER_REASON_NOT_TODAY),
        invalidate: invalidateTask,
        successMessage: t('popover.deferTomorrow'),
        undoLabel: t('common.undo'),
        forwardErrorSource: 'quickAction.defer',
        forwardErrorMessage: 'Failed to defer task',
        forwardErrorToastMessage: t('common.error'),
        undoErrorSource: 'quickAction.undoDefer',
        undoErrorMessage: 'Failed to undo defer',
        undoErrorToastMessage: t('common.error'),
      });
    } finally {
      setActionPending(false);
    }
  }, [actionPending, dayContext.tomorrowYmd, invalidateTask, t, task]);

  const handleDeferNextWeek = useCallback(async () => {
    if (actionPending) return;
    setActionPending(true);
    try {
      await runTaskDeferralWithUndo({
        task,
        runDefer: () => deferTaskUntil(task.id, getNextMondayYmd(dayContext.timezone), DEFER_REASON_NOT_TODAY),
        invalidate: invalidateTask,
        successMessage: t('task.defer.nextWeek'),
        undoLabel: t('common.undo'),
        forwardErrorSource: 'quickAction.deferWeek',
        forwardErrorMessage: 'Failed to defer task',
        forwardErrorToastMessage: t('common.error'),
        undoErrorSource: 'quickAction.undoDeferWeek',
        undoErrorMessage: 'Failed to undo defer next week',
        undoErrorToastMessage: t('common.error'),
      });
    } finally {
      setActionPending(false);
    }
  }, [actionPending, dayContext.timezone, invalidateTask, t, task]);

  const handlePromote = useCallback(async () => {
    if (actionPending) return;
    setActionPending(true);
    try {
      await updateTask(task.id, { status: 'open' });
      invalidateTask();
      toast.success(t('task.promoted'));
    } catch (error) {
      reportClientError('quickAction.promote', 'Failed to promote task', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      setActionPending(false);
    }
  }, [actionPending, invalidateTask, t, task.id]);

  return {
    actionPending,
    canPromote: task.status === TASK_STATUS.someday,
    isActive: isTaskActive(task.status),
    handleDeferNextWeek,
    handleDeferTomorrow,
    handlePromote,
  };
}
