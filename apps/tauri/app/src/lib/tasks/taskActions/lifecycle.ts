import { useCallback } from 'react';

import type { Task } from '@/lib/ipc/tasks/models';
import { cancelTask, completeTask, reopenTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { duplicateTask, updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { reportClientError } from '../../errors/errorLogging';
import {
  applyOptimisticTaskPatch,
  rollbackOptimisticTaskPatch,
} from '../../query/optimisticEntity';
import { invalidateTaskMutationQueries } from '../../query/queryKeys';
import { toast } from '../../notifications/toast';
import { showUndoToastWithRedo } from '../lifecycleUndoRedo';
import { getActiveTask, type TaskListActionDeps, undoableAction } from './shared';
import { TASK_STATUS } from '@lorvex/shared/types';

export function useTaskLifecycleActions({
  tasksRef,
  qc,
  t,
  format,
}: Pick<TaskListActionDeps, 'tasksRef' | 'qc' | 't' | 'format'>) {
  const onComplete = useCallback((taskId: string) => {
    const task = tasksRef.current.find((tk) => tk.id === taskId);
    if (!task) return;

    const isDone = task.status === TASK_STATUS.completed || task.status === TASK_STATUS.cancelled;
    const optimisticStatus: Task['status'] = isDone ? 'open' : 'completed';
    void (async () => {
      const snapshot = await applyOptimisticTaskPatch(qc, taskId, { status: optimisticStatus });
      try {
        if (isDone) {
          await reopenTask(taskId);
          invalidateTaskMutationQueries(qc, { listId: task.list_id });
        } else {
          const result = await completeTask(taskId);
          invalidateTaskMutationQueries(qc, { listId: task.list_id });
          showUndoToastWithRedo(t('task.status.completed'), result.undo_token, {
            invalidate: () => invalidateTaskMutationQueries(qc, { listId: task.list_id }),
            t,
            errorKeyPrefix: 'keyboardAction.complete',
            persist: {
              label: format('task.status.completedNamed', { title: task.title }),
              action: 'complete',
            },
          });
        }
      } catch (error) {
        rollbackOptimisticTaskPatch(qc, snapshot);
        reportClientError('keyboardAction.complete', 'Failed to toggle complete', error);
        toast.errorWithDetail(error, t('common.error'));
      }
    })();
  }, [format, qc, t, tasksRef]);

  const onCancelTask = useCallback((taskId: string) => {
    const task = getActiveTask(tasksRef.current, taskId);
    if (!task) return;

    void cancelTask(taskId)
      .then((result) => {
        invalidateTaskMutationQueries(qc, { listId: task.list_id });
        showUndoToastWithRedo(t('task.status.cancelled'), result.undo_token, {
          invalidate: () => invalidateTaskMutationQueries(qc, { listId: task.list_id }),
          t,
          errorKeyPrefix: 'keyboardAction.cancel',
          persist: {
            label: format('task.status.cancelledNamed', { title: task.title }),
            action: 'cancel',
          },
        });
      })
      .catch((error) => {
        reportClientError('keyboardAction.cancel', 'Failed to cancel task', error);
        toast.errorWithDetail(error, t('common.error'));
      });
  }, [format, qc, t, tasksRef]);

  const onDuplicate = useCallback((taskId: string) => {
    const task = getActiveTask(tasksRef.current, taskId);
    if (!task) return;

    void duplicateTask(taskId)
      .then(() => {
        invalidateTaskMutationQueries(qc, { listId: task.list_id });
        toast.success(t('task.duplicated'));
      })
      .catch((error) => {
        reportClientError('keyboardAction.duplicate', 'Failed to duplicate task', error);
        toast.errorWithDetail(error, t('common.error'));
      });
  }, [qc, t, tasksRef]);

  const onPromoteToActive = useCallback((taskId: string) => {
    const task = tasksRef.current.find((tk) => tk.id === taskId);
    if (!task) return;
    if (task.status !== TASK_STATUS.someday) return;

    undoableAction({
      action: () => updateTask(taskId, { status: 'open' }),
      successMsg: t('task.promoted'),
      errorKey: 'keyboardAction.promote',
      errorMsg: 'Failed to promote task',
      listId: task.list_id,
      qc,
      t,
      optimistic: { taskId, patch: { status: 'open' } },
    });
  }, [qc, t, tasksRef]);

  return {
    onCancelTask,
    onComplete,
    onDuplicate,
    onPromoteToActive,
  };
}
