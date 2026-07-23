import { useCallback, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';
import { reportClientError } from '@/lib/errors/errorLogging';
import type { TranslationKey } from '@/lib/i18n';
import {
  applyOptimisticTaskPatch,
  rollbackOptimisticTaskPatch,
  type TaskPatch,
} from '@/lib/query/optimisticEntity';
import { invalidateTaskWorkspaceQueries } from '@/lib/query/queryKeys';
import { toast } from '@/lib/notifications/toast';

interface UseCalendarTaskActionsArgs {
  t: (key: TranslationKey) => string;
}

export function useCalendarTaskActions({ t }: UseCalendarTaskActionsArgs) {
  const queryClient = useQueryClient();
  const rescheduleInFlight = useRef(false);

  const handleRescheduleTask = useCallback(async (taskId: string, newDate: string, oldDate: string | null, hasPlannedDate?: boolean) => {
    if (rescheduleInFlight.current) return;
    if (oldDate === newDate) return;
    rescheduleInFlight.current = true;
    const patch: TaskUpdatePatch = hasPlannedDate ? { planned_date: newDate } : { due_date: newDate };
    const optimisticPatch: TaskPatch = hasPlannedDate ? { planned_date: newDate } : { due_date: newDate };
    // Drag-to-reschedule on a calendar cell is one of the most
    // visually sensitive actions: the task pill is literally being
    // released onto a new day, and seeing it snap back to the source
    // cell for ~200ms before hopping to the destination is jarring.
    // Patch the cache optimistically so the pill stays put under the
    // cursor while the IPC round-trips.
    const snapshot = await applyOptimisticTaskPatch(queryClient, taskId, optimisticPatch);
    try {
      await updateTask(taskId, patch);
      invalidateTaskWorkspaceQueries(queryClient);
      toast.success(
        t('calendar.taskRescheduled'),
        oldDate
          ? {
              label: t('common.undo'),
              onClick: async () => {
                try {
                  await updateTask(taskId, hasPlannedDate ? { planned_date: oldDate } : { due_date: oldDate });
                  invalidateTaskWorkspaceQueries(queryClient);
                } catch (undoError) {
                  reportClientError(
                    'calendar.undoReschedule',
                    'Failed to undo calendar reschedule',
                    undoError,
                  );
                  toast.errorWithDetail(undoError, t('common.error'));
                }
              },
            }
          : undefined,
      );
    } catch (error) {
      rollbackOptimisticTaskPatch(queryClient, snapshot);
      reportClientError('calendar.rescheduleTask', 'Failed to reschedule task via drag', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      rescheduleInFlight.current = false;
    }
  }, [queryClient, t]);

  // Week-timeline drop: set BOTH the column date and the Y-inferred time in a
  // single update. The day axis routes to `planned_date` vs `due_date` the same
  // way day-only drops do; `due_time` always carries the snapped time so a
  // same-day re-time lands the task at its new slot.
  const handleRescheduleTaskAt = useCallback(
    async (
      taskId: string,
      newDate: string,
      oldDate: string | null,
      oldTime: string | null,
      dueTime: string,
      hasPlannedDate?: boolean,
    ) => {
      if (rescheduleInFlight.current) return;
      rescheduleInFlight.current = true;
      const dateKey = hasPlannedDate ? 'planned_date' : 'due_date';
      const patch: TaskUpdatePatch = { [dateKey]: newDate, due_time: dueTime };
      const optimisticPatch: TaskPatch = { [dateKey]: newDate, due_time: dueTime };
      const snapshot = await applyOptimisticTaskPatch(queryClient, taskId, optimisticPatch);
      try {
        await updateTask(taskId, patch);
        invalidateTaskWorkspaceQueries(queryClient);
        // Offer undo only when the source had a day to restore to; the time
        // axis goes back to its pre-drop value (null when the task was untimed).
        toast.success(
          `${t('calendar.taskRescheduled')} -> ${dueTime}`,
          oldDate
            ? {
                label: t('common.undo'),
                onClick: async () => {
                  try {
                    await updateTask(taskId, { [dateKey]: oldDate, due_time: oldTime });
                    invalidateTaskWorkspaceQueries(queryClient);
                  } catch (undoError) {
                    reportClientError(
                      'calendar.undoRescheduleAt',
                      'Failed to undo week-timeline reschedule',
                      undoError,
                    );
                    toast.errorWithDetail(undoError, t('common.error'));
                  }
                },
              }
            : undefined,
        );
      } catch (error) {
        rollbackOptimisticTaskPatch(queryClient, snapshot);
        reportClientError('calendar.rescheduleTaskAt', 'Failed to reschedule task via week drag', error);
        toast.errorWithDetail(error, t('common.error'));
      } finally {
        rescheduleInFlight.current = false;
      }
    },
    [queryClient, t],
  );

  return {
    handleRescheduleTask,
    handleRescheduleTaskAt,
  };
}
