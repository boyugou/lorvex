import { useMutation, useQueryClient } from '@tanstack/react-query';
import { toUserFacingErrorMessage } from '@/lib/ipc/core.logic';
import type { Task } from '@/lib/ipc/tasks/models';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { invalidateTaskMutationQueries } from '@/lib/query/queryKeys';
import { toast } from '@/lib/notifications/toast';

/**
 * Bespoke `useMutation` site (allowlisted by
 * `useMutationDirectImports.contract.test.ts`).
 *
 * The "reschedule overdue" batch action fans an array of task ids out
 * to `updateTask` via `Promise.allSettled`, then synthesises an
 * `AggregateError` carrying a `partial` flag + per-task reason list to
 * distinguish partial failure (toast.warning + partial cache
 * invalidation) from total failure (toast.error, no cache write).
 * Neither shape fits `defineEntityHooks`:
 *   - `run` produces a single Promise; allSettled fan-out is the
 *     point of the IPC contract here.
 *   - The error path branches on `error.partial` and chooses between
 *     toast lanes + conditional invalidation; the factory's standard
 *     "report + toast" handler can't express that branch.
 * Invalidation still goes through the centralized
 * `invalidateTaskMutationQueries` helper, so future fan-outs reuse one
 * key set.
 */
export function useDashboardSectionActions() {
  const queryClient = useQueryClient();
  const dayContext = useConfiguredDayContext();
  const { t, format } = useI18n();

  const rescheduleOverdueToToday = useMutation({
    mutationFn: async (tasks: Task[]) => {
      const todayYmd = dayContext.todayYmd;
      // "Reschedule overdue to today" means "plan to work on it today" while
      // preserving the original due date as the external deadline.
      const results = await Promise.allSettled(
        tasks.map((task) => updateTask(task.id, { planned_date: todayYmd })),
      );
      const failed = results.filter((result): result is PromiseRejectedResult => result.status === 'rejected');
      if (failed.length > 0) {
        const reasons = failed
          .map((result) => toUserFacingErrorMessage(result.reason, ''))
          .filter((line) => line.length > 0);
        const summary = format('today.rescheduleOverduePartialFailure', {
          failed: failed.length,
          total: tasks.length,
        });
        const detail = reasons.length > 0 ? `${summary}: ${reasons.join('; ')}` : summary;
        // The thrown AggregateError carries both `.message` (the
        // user-facing prose surfaced by `toUserFacingErrorMessage`)
        // and a `.partial` flag the `onError` handler reads to route
        // to `toast.warning` for mixed outcomes vs. `toast.error`
        // when every reschedule rejected (,).
        const aggregate = new AggregateError(failed.map((result) => result.reason), detail);
        (aggregate as AggregateError & { partial?: boolean }).partial =
          failed.length < tasks.length;
        throw aggregate;
      }
    },
    onSuccess: () => {
      invalidateTaskMutationQueries(queryClient);
    },
    onError: (error, tasks) => {
      reportClientError(
        'today.rescheduleOverdue',
        `Failed to reschedule overdue tasks (${tasks.length})`,
        error,
      );
      // distinguish partial failure (some rescheduled, some
      // rejected) from total failure. Partial flows through
      // `toast.warning` because the operation produced a mixed
      // outcome the user must address — it's not an error in the
      // "nothing happened" sense, and the amber lane keeps it
      // visually distinct from the all-or-nothing red. Total
      // failure stays on the error lane.
      const message = toUserFacingErrorMessage(error, t('common.error'));
      const isPartial =
        error instanceof AggregateError &&
        (error as AggregateError & { partial?: boolean }).partial === true;
      if (isPartial) {
        // Some reschedules landed — refresh the cache so the row
        // movement is reflected in Today even though we throw to
        // surface the failures.
        invalidateTaskMutationQueries(queryClient);
        toast.warning(message);
      } else {
        toast.error(message);
      }
    },
  });

  return {
    handleRescheduleOverdueToToday: (tasks: Task[]) => {
      if (rescheduleOverdueToToday.isPending || tasks.length === 0) {
        return;
      }
      rescheduleOverdueToToday.mutate(tasks);
    },
    isReschedulingOverdue: rescheduleOverdueToToday.isPending,
  };
}
