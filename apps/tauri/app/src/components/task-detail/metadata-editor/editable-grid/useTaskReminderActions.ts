import { useCallback, useMemo } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { addTaskReminder, removeTaskReminder } from '@/lib/ipc/tasks/mutations/reminders';
import { getTaskReminders } from '@/lib/ipc/tasks/queries';
import { QUERY_KEYS, invalidateTaskReminderQueries } from '@/lib/query/queryKeys';
import { isoFromDatetimeLocalInTimezone } from '@/lib/dayContextMath';
import { reportTaskDetailActionError } from '@/components/task-detail/support';

interface UseTaskReminderActionsArgs {
  taskId: string;
  /**
   * Configured app timezone (IANA). The reminder input is a `datetime-local`
   * string that the user reads as wall-clock time in this timezone, so we
   * must interpret it under `timezone` when converting to UTC ISO. Falling
   * back to `new Date(value)` would treat the wall time as host-browser
   * timezone and fire reminders hours off for travelers / dual-system users.
   */
  timezone: string;
}

export function useTaskReminderActions({
  taskId,
  timezone,
}: UseTaskReminderActionsArgs) {
  const queryClient = useQueryClient();

  const { data: reminders = [] } = useQuery({
    queryKey: QUERY_KEYS.taskReminders(taskId),
    queryFn: ({ signal }) => getTaskReminders(taskId, signal),
    staleTime: 10_000,
  });

  const pendingReminders = useMemo(
    () => reminders.filter((reminder) => !reminder.dismissed_at && !reminder.cancelled_at),
    [reminders],
  );

  const invalidate = useCallback(() => {
    invalidateTaskReminderQueries(queryClient, taskId);
  }, [queryClient, taskId]);

  const handleRemoveReminder = useCallback(async (reminderId: string) => {
    try {
      await removeTaskReminder(taskId, reminderId);
      invalidate();
    } catch (error) {
      reportTaskDetailActionError('remove-reminder', error, taskId);
    }
  }, [invalidate, taskId]);

  const handleAddReminder = useCallback(async (value: string) => {
    // Interpret the `datetime-local` wall time in the configured app
    // timezone, not the host browser TZ — see the `timezone` arg JSDoc.
    const isoUtc = isoFromDatetimeLocalInTimezone(value, timezone);
    if (!isoUtc) {
      return false;
    }

    try {
      await addTaskReminder(taskId, isoUtc);
      invalidate();
      return true;
    } catch (error) {
      reportTaskDetailActionError('add-reminder', error, taskId);
      return false;
    }
  }, [invalidate, taskId, timezone]);

  return {
    pendingReminders,
    reminders,
    handleAddReminder,
    handleRemoveReminder,
  };
}
