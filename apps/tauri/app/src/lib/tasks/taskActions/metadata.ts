import { useCallback } from 'react';

import type { Task } from '@/lib/ipc/tasks/models';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import {
  getActiveTask,
  type TaskListActionDeps,
  undoableAction,
  WEEKLY_RECURRENCE,
  WEEKLY_RECURRENCE_PATCH,
} from './shared';

export function useTaskMetadataActions({
  tasksRef,
  qc,
  t,
}: Pick<TaskListActionDeps, 'tasksRef' | 'qc' | 't'>) {
  const onSetPriority = useCallback((taskId: string, priority: NonNullable<Task['priority']>) => {
    const task = getActiveTask(tasksRef.current, taskId);
    if (!task) return;
    const newPriority = task.priority === priority ? null : priority;

    undoableAction({
      action: () => updateTask(taskId, { priority: newPriority }),
      successMsg: newPriority ? `P${newPriority}` : t('task.noPriority'),
      errorKey: 'keyboardAction.priority',
      errorMsg: 'Failed to set priority',
      listId: task.list_id,
      qc,
      t,
      optimistic: { taskId, patch: { priority: newPriority } },
    });
  }, [qc, t, tasksRef]);

  const onToggleRecurrence = useCallback((taskId: string) => {
    const task = getActiveTask(tasksRef.current, taskId);
    if (!task) return;

    const hasRecurrence = !!task.recurrence;
    const updateRecurrence = hasRecurrence ? null : WEEKLY_RECURRENCE_PATCH;
    const optimisticRecurrence = hasRecurrence ? null : WEEKLY_RECURRENCE;
    undoableAction({
      action: () => updateTask(taskId, { recurrence: updateRecurrence }),
      successMsg: hasRecurrence ? t('contextMenu.recurrenceCleared') : t('contextMenu.recurrenceSet'),
      errorKey: 'keyboardAction.recurrence',
      errorMsg: 'Failed to toggle recurrence',
      listId: task.list_id,
      qc,
      t,
      optimistic: { taskId, patch: { recurrence: optimisticRecurrence } },
    });
  }, [qc, t, tasksRef]);

  return {
    onSetPriority,
    onToggleRecurrence,
  };
}
