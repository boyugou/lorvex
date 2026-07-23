import { useCallback, useState, type MouseEvent } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { completeTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { dismissFocusSchedule, updateFocusScheduleBlocks } from '@/lib/ipc/tasks/reviews';
import type { FocusScheduleWithTasks } from '@/lib/ipc/tasks/models';
import { reportClientError } from '@/lib/errors/errorLogging';
import type { TranslationKey } from '@/lib/i18n';
import {
  invalidateCurrentFocusQueries,
  invalidateFocusScheduleQueries,
  invalidateFocusTaskQueries,
  invalidatePlanningFocusQueries,
  invalidateTaskMutationQueries,
} from '@/lib/query/queryKeys';
import { toast } from '@/lib/notifications/toast';
import { moveTaskInBlocks, removeTaskFromBlocks } from './blocks';

interface UseScheduleTimelineActionsArgs {
  blocks: FocusScheduleWithTasks['blocks'];
  t: (key: TranslationKey) => string;
}

export function useScheduleTimelineActions({
  blocks,
  t,
}: UseScheduleTimelineActionsArgs) {
  const queryClient = useQueryClient();
  const [completingIds, setCompletingIds] = useState<string[]>([]);

  const dismissMutation = useMutation({
    mutationFn: () => dismissFocusSchedule(),
    onSuccess: () => {
      invalidateFocusScheduleQueries(queryClient);
    },
    onError: (error) => {
      reportClientError('schedule.dismiss', 'Failed to dismiss focus schedule', error, undefined, 'warn');
      toast.errorWithDetail(error, t('common.error'));
    },
  });

  const removeMutation = useMutation({
    mutationFn: (taskId: string) => {
      const newBlocks = removeTaskFromBlocks(blocks, taskId);
      return updateFocusScheduleBlocks(newBlocks);
    },
    onSuccess: () => {
      // removing a block from the schedule doesn't just
      // affect focusSchedule + currentFocus — the task's today-surface
      // representation (planned or not) and any list-view card that
      // showed the task as scheduled need to refresh too.
      invalidateFocusScheduleQueries(queryClient);
      invalidateCurrentFocusQueries(queryClient);
      invalidateTaskMutationQueries(queryClient, {});
    },
    onError: (error) => {
      reportClientError('schedule.removeBlock', 'Failed to remove block from schedule', error, undefined, 'warn');
      toast.errorWithDetail(error, t('common.error'));
    },
  });

  const moveMutation = useMutation({
    mutationFn: ({ taskId, direction }: { taskId: string; direction: 'up' | 'down' }) => {
      const newBlocks = moveTaskInBlocks(blocks, taskId, direction);
      return updateFocusScheduleBlocks(newBlocks);
    },
    onSuccess: () => {
      // Reordering a block changes which task lands in which slot,
      // which in turn shifts every other today-surface card's
      // "scheduled at HH:MM" badge. Mirror removeMutation's broader
      // invalidation so the day view, task detail, and any list-view
      // card stay in sync without waiting for the Rust data-changed
      // broadcast.
      invalidateFocusScheduleQueries(queryClient);
      invalidateCurrentFocusQueries(queryClient);
      invalidateTaskMutationQueries(queryClient, {});
    },
    onError: (error) => {
      reportClientError('schedule.moveBlock', 'Failed to move block in schedule', error, undefined, 'warn');
      toast.errorWithDetail(error, t('common.error'));
    },
  });

  const handleCompleteTask = useCallback((taskId: string, event: MouseEvent) => {
    event.stopPropagation();
    setCompletingIds((previous) => {
      if (previous.includes(taskId)) return previous;
      return [...previous, taskId];
    });
    // the schedule-timeline completeTask path was raw
    // IPC with only planning-focus invalidation. Any open Task Detail
    // / All-Tasks / list view rendering that task stayed stale until
    // the Rust data-changed round-trip landed — a visible "just
    // clicked complete and the other surface still says open" gap.
    // Use the dedicated focus-task helper which covers today-surface
    // + task-collection + the per-task queries.
    completeTask(taskId)
      .then(() => {
        // Reset the optimistic completing flag once the IPC round-trip
        // succeeds. Without this, a subsequent click on the same block
        // (e.g. after the user undid completion in another surface and
        // the schedule re-renders the same task_id) would short-circuit
        // because the previous run's id was still in completingIds.
        setCompletingIds((previous) => previous.filter((id) => id !== taskId));
        invalidatePlanningFocusQueries(queryClient);
        invalidateFocusTaskQueries(queryClient, { taskId });
      })
      .catch((error) => {
        setCompletingIds((previous) => previous.filter((id) => id !== taskId));
        reportClientError('schedule.completeTask', 'Failed to complete task from schedule', error, undefined, 'warn');
        toast.errorWithDetail(error, t('common.error'));
      });
  }, [queryClient, t]);

  const handleDismissSchedule = useCallback(() => {
    dismissMutation.mutate();
  }, [dismissMutation]);

  const handleMoveTask = useCallback((
    taskId: string,
    direction: 'up' | 'down',
    event: MouseEvent,
  ) => {
    event.stopPropagation();
    moveMutation.mutate({ taskId, direction });
  }, [moveMutation]);

  const handleRemoveTask = useCallback((taskId: string, event: MouseEvent) => {
    event.stopPropagation();
    removeMutation.mutate(taskId);
  }, [removeMutation]);

  return {
    completingIds,
    dismissMutation,
    handleCompleteTask,
    handleDismissSchedule,
    handleMoveTask,
    handleRemoveTask,
  };
}
