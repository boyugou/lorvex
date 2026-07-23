import { useCallback } from 'react';

import { getNextMondayYmd } from '../../dayContextMath';
import { deferTaskUntil } from '@/lib/ipc/tasks/mutations/deferral';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import type { TaskPatch } from '../../query/optimisticEntity';
import { invalidateTaskMutationQueries } from '../../query/queryKeys';
import { buildDueDatePatch } from '../dueAtPatch.logic';
import { runTaskDeferralWithUndo } from '../deferralUndo';
import { DEFER_REASON_NOT_TODAY, getActiveTask, type TaskListActionDeps, undoableAction } from './shared';

export function useTaskSchedulingActions({
  tasksRef,
  dayContextRef,
  qc,
  t,
}: Pick<TaskListActionDeps, 'tasksRef' | 'dayContextRef' | 'qc' | 't'>) {
  const runDefer = useCallback(
    (
      taskId: string,
      targetYmd: string,
      successMsgKey: 'popover.deferTomorrow' | 'common.deferNextWeek',
      errorVariant: 'defer' | 'deferNextWeek',
    ) => {
      const task = getActiveTask(tasksRef.current, taskId);
      if (!task) return;

      const errorKey = errorVariant === 'defer'
        ? 'keyboardAction.defer'
        : 'keyboardAction.deferNextWeek';
      const undoErrorKey = errorVariant === 'defer'
        ? 'keyboardAction.undoDefer'
        : 'keyboardAction.undoDeferNextWeek';
      const errorMsg = errorVariant === 'defer'
        ? 'Failed to defer task'
        : 'Failed to defer task to next week';
      const undoErrorMsg = errorVariant === 'defer'
        ? 'Failed to undo defer'
        : 'Failed to undo defer next week';

      void runTaskDeferralWithUndo({
        task,
        runDefer: () => deferTaskUntil(taskId, targetYmd, DEFER_REASON_NOT_TODAY),
        invalidate: () => invalidateTaskMutationQueries(qc, { listId: task.list_id }),
        successMessage: t(successMsgKey),
        undoLabel: t('common.undo'),
        forwardErrorSource: errorKey,
        forwardErrorMessage: errorMsg,
        forwardErrorToastMessage: t('common.error'),
        undoErrorSource: undoErrorKey,
        undoErrorMessage: undoErrorMsg,
        undoErrorToastMessage: t('common.error'),
      });
    },
    [qc, t, tasksRef],
  );

  const onDefer = useCallback(
    (taskId: string) => {
      runDefer(
        taskId,
        dayContextRef.current.tomorrowYmd,
        'popover.deferTomorrow',
        'defer',
      );
    },
    [dayContextRef, runDefer],
  );

  const onDeferNextWeek = useCallback(
    (taskId: string) => {
      runDefer(
        taskId,
        getNextMondayYmd(dayContextRef.current.timezone),
        'common.deferNextWeek',
        'deferNextWeek',
      );
    },
    [dayContextRef, runDefer],
  );

  const onSetDueToday = useCallback((taskId: string) => {
    const task = getActiveTask(tasksRef.current, taskId);
    if (!task) return;

    const todayYmd = dayContextRef.current.todayYmd;
    const newDueDate = task.due_date === todayYmd ? null : todayYmd;
    const duePatch = buildDueDatePatch(task, newDueDate);
    undoableAction({
      action: () => updateTask(taskId, duePatch),
      successMsg: newDueDate ? t('contextMenu.dueToday') : t('contextMenu.dueDateCleared'),
      errorKey: 'keyboardAction.dueToday',
      errorMsg: 'Failed to set due date',
      listId: task.list_id,
      qc,
      t,
      optimistic: { taskId, patch: duePatch as TaskPatch },
    });
  }, [dayContextRef, qc, t, tasksRef]);

  const onSetDueTomorrow = useCallback((taskId: string) => {
    const task = getActiveTask(tasksRef.current, taskId);
    if (!task) return;

    const tomorrowYmd = dayContextRef.current.tomorrowYmd;
    undoableAction({
      action: () => updateTask(taskId, { due_date: tomorrowYmd }),
      successMsg: t('contextMenu.dueTomorrow'),
      errorKey: 'keyboardAction.dueTomorrow',
      errorMsg: 'Failed to set due date',
      listId: task.list_id,
      qc,
      t,
      optimistic: { taskId, patch: { due_date: tomorrowYmd } },
    });
  }, [dayContextRef, qc, t, tasksRef]);

  return {
    onDefer,
    onDeferNextWeek,
    onSetDueToday,
    onSetDueTomorrow,
  };
}
