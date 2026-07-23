import { useMutation, useQueryClient } from '@tanstack/react-query';
import type { Task } from '@/lib/ipc/tasks/models';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { reportClientError } from '@/lib/errors/errorLogging';
import type { TranslationKey } from '@/lib/i18n';
import {
  applyOptimisticTaskPatch,
  rollbackOptimisticTaskPatch,
  type OptimisticTaskSnapshot,
} from '@/lib/query/optimisticEntity';
import { invalidateTaskStatusChangeQueries } from '@/lib/query/queryKeys';
import { buildDueDatePatch } from '@/lib/tasks/dueAtPatch.logic';
import { toast } from '@/lib/notifications/toast';

interface UseEisenhowerPriorityActionsArgs {
  t: (key: TranslationKey) => string;
}

/**
 * Eisenhower view actions.
 *
 * Both `changePriority` and `changeDueDate` use the shared
 * `applyOptimisticTaskPatch` helper: the helper sweeps every
 * task-bearing query in the cache (not just the all-tasks key) and
 * captures a per-field, per-task snapshot so concurrent in-flight
 * mutations on disjoint fields/tasks compose without clobbering each
 * other on rollback. The hand-rolled rollback only patched
 * the all-tasks key and snapshotted the entire `Task[]` array, which
 * silently reverted unrelated optimistic patches that had landed in
 * the same array between snapshot and rollback.
 */
export function useEisenhowerPriorityActions({
  t,
}: UseEisenhowerPriorityActionsArgs) {
  const queryClient = useQueryClient();

  type TaskPriority = NonNullable<Task['priority']>;

  const changePriority = useMutation<
    unknown,
    Error,
    { taskId: string; priority: TaskPriority },
    { snapshot: OptimisticTaskSnapshot } | undefined
  >({
    mutationFn: async ({ taskId, priority }) =>
      updateTask(taskId, { priority }),
    onMutate: async ({ taskId, priority }) => {
      const snapshot = await applyOptimisticTaskPatch(queryClient, taskId, {
        priority: priority as Task['priority'],
      });
      return { snapshot };
    },
    onSuccess: () => {
      invalidateTaskStatusChangeQueries(queryClient);
      toast.success(t('eisenhower.moved'));
    },
    onError: (error, _variables, context) => {
      if (context) rollbackOptimisticTaskPatch(queryClient, context.snapshot);
      reportClientError('eisenhower', 'Failed to update task priority', error);
      toast.errorWithDetail(error, t('common.error'));
    },
  });

  const changeDueDate = useMutation<
    unknown,
    Error,
    { task: Task; dueDate: string | null },
    { snapshot: OptimisticTaskSnapshot } | undefined
  >({
    mutationFn: async ({ task, dueDate }) =>
      updateTask(task.id, buildDueDatePatch(task, dueDate)),
    onMutate: async ({ task, dueDate }) => {
      const patch = buildDueDatePatch(task, dueDate);
      const snapshot = await applyOptimisticTaskPatch(queryClient, task.id, patch);
      return { snapshot };
    },
    onSuccess: () => {
      invalidateTaskStatusChangeQueries(queryClient);
      toast.success(t('eisenhower.moved'));
    },
    onError: (error, _variables, context) => {
      if (context) rollbackOptimisticTaskPatch(queryClient, context.snapshot);
      reportClientError('eisenhower', 'Failed to update task due date', error);
      toast.errorWithDetail(error, t('common.error'));
    },
  });

  return {
    handleChangePriority: (taskId: string, priority: TaskPriority) => {
      changePriority.mutate({ taskId, priority });
    },
    handleChangeDueDate: (task: Task, dueDate: string | null) => {
      changeDueDate.mutate({ task, dueDate });
    },
    isChangingPriority: changePriority.isPending,
    isChangingDueDate: changeDueDate.isPending,
  };
}
