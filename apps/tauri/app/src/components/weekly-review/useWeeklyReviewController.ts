import { useState, useMemo } from 'react';
import { useMounted } from '@/lib/useMounted';

import { useQuery, useQueryClient } from '@tanstack/react-query';

import { confirm } from '@/lib/dialogs/confirm';
import { reportClientError } from '@/lib/errors/errorLogging';
import { getEventsByDateRange } from '@/lib/ipc/calendar';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { getTodaysHabits } from '@/lib/ipc/habits';
import type { HabitSummary } from '@/lib/ipc/habits';
import { shelveList as shelveListIpc } from '@/lib/ipc/tasks/lists';
import type { StalledList, Task } from '@/lib/ipc/tasks/models';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { getUpcomingTasks } from '@/lib/ipc/tasks/queries';
import { getOverview, getWeeklyReview } from '@/lib/ipc/tasks/reviews';
import { useI18n } from '@/lib/i18n';
import { DAY_SCOPED_QUERY_KEYS } from '@/lib/query/dayScopedQueryKeys';
import { QUERY_KEYS, invalidateTaskWorkspaceQueries } from '@/lib/query/queryKeys';
import { daysBetween } from '@/lib/timeUtils';
import { toast } from '@/lib/notifications/toast';
import { useConfiguredDayContext, type DayContext } from '@/lib/dayContext';
import { addYmdDays, ymdFromDateParts } from '@/lib/dayContextMath';
import { formatCalendarDate } from '@/lib/dates/dateLocale';

export interface WeeklyReviewViewProps {
  onSelectTask: (taskId: string) => void;
  onOpenList?: ((listId: string) => void) | undefined;
}

export type DeferredInterventionAction = 'schedule_tomorrow' | 'retriage' | 'archive';

/** Overdue tasks grouped by severity tier. */
export interface OverdueSeverityGroup {
  label: 'week' | 'two_weeks' | 'month_plus';
  tasks: Task[];
}

/** Completed tasks grouped by day. */
export interface CompletionDayGroup {
  dateYmd: string;
  dayLabel: string;
  tasks: Task[];
  totalMinutes: number;
}

export const WEEKLY_REVIEW_LOOKING_AHEAD_DAYS = 7;

export interface WeeklyReviewLookingAheadWindow {
  startYmd: string;
  endYmd: string;
}

export function getWeeklyReviewLookingAheadWindow(todayYmd: string): WeeklyReviewLookingAheadWindow {
  return {
    startYmd: addYmdDays(todayYmd, 1),
    endYmd: addYmdDays(todayYmd, WEEKLY_REVIEW_LOOKING_AHEAD_DAYS),
  };
}

export interface WeeklyReviewControllerState {
  dayContext: DayContext;
  shelvingListId: string | null;
  deferredActionByTaskId: Record<string, DeferredInterventionAction | undefined>;
  isError: boolean;
  isLoading: boolean;
  locale: string;
  onOpenList?: ((listId: string) => void) | undefined;
  onSelectTask: (taskId: string) => void;
  refetch: () => void;
  review: Awaited<ReturnType<typeof getWeeklyReview>> | undefined;
  runDeferredIntervention: (task: Task, action: DeferredInterventionAction) => Promise<void>;
  t: ReturnType<typeof useI18n>['t'];
  shelveList: (stalledList: StalledList) => Promise<void>;
  // New enriched data
  completionsByDay: CompletionDayGroup[];
  overdueBySeverity: OverdueSeverityGroup[];
  upcomingNextWeek: Task[];
  nextWeekEvents: UnifiedCalendarEvent[];
  habits: HabitSummary[];
  completedLastWeek: number;
  totalFocusMinutes: number;
  habitsCompletionRate: number | null;
  // Task inline actions
  inlineActionByTaskId: Record<string, 'complete' | 'cancel' | undefined>;
  completeTask: (task: Task) => Promise<void>;
  cancelTask: (task: Task) => Promise<void>;
}

export function useWeeklyReviewController({
  onSelectTask,
  onOpenList,
}: WeeklyReviewViewProps): WeeklyReviewControllerState {
  const queryClient = useQueryClient();
  const { t, format, locale } = useI18n();
  const dayContext = useConfiguredDayContext();
  const [shelvingListId, setShelvingListId] = useState<string | null>(null);
  const [deferredActionByTaskId, setDeferredActionByTaskId] = useState<Record<string, DeferredInterventionAction | undefined>>({});
  const [inlineActionByTaskId, setInlineActionByTaskId] = useState<Record<string, 'complete' | 'cancel' | undefined>>({});
  const weeklyReviewMountedRef = useMounted();

  const {
    data: review,
    isLoading,
    isError,
    refetch,
  } = useQuery({
    queryKey: DAY_SCOPED_QUERY_KEYS.weeklyReview(dayContext.todayYmd),
    queryFn: ({ signal }) => getWeeklyReview(signal),
  });

  // Fetch upcoming tasks and calendar events for the same next-seven-day window.
  const { startYmd: nextWeekStart, endYmd: nextWeekEnd } =
    getWeeklyReviewLookingAheadWindow(dayContext.todayYmd);
  const { data: upcomingNextWeek = [] } = useQuery({
    queryKey: QUERY_KEYS.weeklyReviewUpcoming(nextWeekStart, nextWeekEnd),
    queryFn: ({ signal }) => getUpcomingTasks(WEEKLY_REVIEW_LOOKING_AHEAD_DAYS, signal),
  });

  const { data: nextWeekEvents = [] } = useQuery({
    queryKey: QUERY_KEYS.weeklyReviewEvents(nextWeekStart, nextWeekEnd),
    queryFn: ({ signal }) => getEventsByDateRange(nextWeekStart, nextWeekEnd, signal),
  });

  // Fetch today's habits to compute completion rate
  const { data: habits = [] } = useQuery({
    queryKey: DAY_SCOPED_QUERY_KEYS.weeklyReviewHabits(dayContext.todayYmd),
    queryFn: ({ signal }) => getTodaysHabits(signal),
  });

  // Fetch overview for last week's completed count
  const { data: overview } = useQuery({
    queryKey: QUERY_KEYS.overview(),
    queryFn: ({ signal }) => getOverview(signal),
  });

  const completedLastWeek = overview?.stats.completed_last_week ?? 0;

  // Compute habits completion rate
  const habitsCompletionRate = useMemo(() => {
    if (habits.length === 0) return null;
    const completed = habits.filter((h) => h.completions_today >= h.target_count).length;
    return Math.round((completed / habits.length) * 100);
  }, [habits]);

  // Group completed tasks by day. Each `completed_at` RFC 3339
  // timestamp is converted to a local YMD in the user's configured
  // timezone (via `ymdFromDateParts`) before grouping so "what I
  // did today" matches the local day. A naive `slice(0, 10)` would
  // yield UTC calendar days, pushing late-evening or early-morning
  // completions into the wrong group for any non-UTC user.
  const completionsByDay = useMemo<CompletionDayGroup[]>(() => {
    if (!review?.completed_this_week.length) return [];

    const groups = new Map<string, Task[]>();
    for (const task of review.completed_this_week) {
      let dateStr = 'unknown';
      if (task.completed_at) {
        const parsed = new Date(task.completed_at);
        if (!Number.isNaN(parsed.valueOf())) {
          dateStr = ymdFromDateParts(parsed, dayContext.timezone);
        } else {
          // Malformed completed_at — fall back to the raw string's
          // date prefix rather than tossing the task entirely.
          dateStr = task.completed_at.slice(0, 10);
        }
      }
      const existing = groups.get(dateStr);
      if (existing) {
        existing.push(task);
      } else {
        groups.set(dateStr, [task]);
      }
    }

    const result: CompletionDayGroup[] = [];
    for (const [dateYmd, tasks] of groups.entries()) {
      // `formatCalendarDate` anchors at UTC midnight + `timeZone:
      // 'UTC'` so the day label stays on the intended calendar day
      // regardless of host OS tz vs app-configured tz.
      const dayLabel = formatCalendarDate(dateYmd, locale, {
        weekday: 'long', month: 'short', day: 'numeric',
      });
      const totalMinutes = tasks.reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0);
      result.push({ dateYmd, dayLabel, tasks, totalMinutes });
    }

    // Sort by date descending (most recent first)
    result.sort((a, b) => b.dateYmd.localeCompare(a.dateYmd));
    return result;
  }, [review?.completed_this_week, locale, dayContext.timezone]);

  // Compute total estimated time from completed tasks
  const totalFocusMinutes = useMemo(() => {
    return (review?.completed_this_week ?? []).reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0);
  }, [review?.completed_this_week]);

  // Group overdue tasks by severity
  const overdueBySeverity = useMemo<OverdueSeverityGroup[]>(() => {
    if (!review?.overdue_tasks.length) return [];

    const todayYmd = dayContext.todayYmd;
    const week: Task[] = [];
    const twoWeeks: Task[] = [];
    const monthPlus: Task[] = [];

    for (const task of review.overdue_tasks) {
      if (!task.due_date) continue;
      const daysOverdue = daysBetween(task.due_date, todayYmd);
      if (daysOverdue >= 30) {
        monthPlus.push(task);
      } else if (daysOverdue >= 14) {
        twoWeeks.push(task);
      } else {
        week.push(task);
      }
    }

    const groups: OverdueSeverityGroup[] = [];
    if (monthPlus.length > 0) groups.push({ label: 'month_plus', tasks: monthPlus });
    if (twoWeeks.length > 0) groups.push({ label: 'two_weeks', tasks: twoWeeks });
    if (week.length > 0) groups.push({ label: 'week', tasks: week });
    return groups;
  }, [review?.overdue_tasks, dayContext.todayYmd]);

  const shelveList = async (stalledList: StalledList) => {
    if (shelvingListId) return;
    const confirmed = await confirm({
      title: t('review.shelveToSomeday'),
      message: t('review.confirmShelveToSomeday'),
      variant: 'danger',
    });
    if (!confirmed) return;
    setShelvingListId(stalledList.id);
    try {
      const result = await shelveListIpc(stalledList.id);
      if (result.shelved_count === 0) {
        toast.info(t('review.noActiveTasks'));
        return;
      }
      invalidateTaskWorkspaceQueries(queryClient);
      toast.success(format('review.shelvedToSomedayNamed', { list: stalledList.name }));
      // Surface the LWW-rejected / concurrently-mutated rows so the
      // user knows the operation didn't land for every open task —
      // the affected rows reconverge on the next sync apply tick.
      if (result.skipped_task_ids.length > 0) {
        toast.info(format('review.shelveSkipped', { count: result.skipped_task_ids.length }));
      }
    } catch (error) {
      reportClientError('weeklyReview.shelveList', 'Failed to shelve stalled list', error, stalledList.id);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (weeklyReviewMountedRef.current) {
        setShelvingListId(null);
      }
    }
  };

  const runDeferredIntervention = async (task: Task, action: DeferredInterventionAction) => {
    if (deferredActionByTaskId[task.id]) return;

    setDeferredActionByTaskId((prev) => ({ ...prev, [task.id]: action }));
    try {
      if (action === 'schedule_tomorrow') {
        await updateTask(task.id, { status: 'open', planned_date: dayContext.tomorrowYmd });
        toast.success(format('review.deferScheduledNamed', { title: task.title }));
      } else if (action === 'retriage') {
        await updateTask(task.id, { status: 'open', planned_date: null });
        toast.success(format('review.deferRescopedNamed', { title: task.title }));
      } else {
        await updateTask(task.id, { status: 'someday' });
        toast.success(format('review.deferArchivedNamed', { title: task.title }));
      }
      invalidateTaskWorkspaceQueries(queryClient);
    } catch (error) {
      reportClientError(
        'weeklyReview.deferredIntervention',
        `Failed to run deferred intervention: ${action}`,
        error,
        task.id,
      );
      // include the backend failure reason on deferred
      // interventions so the user knows if the task was already closed,
      // the list was deleted, or the DB was busy.
      toast.errorWithDetail(error, t('review.deferActionError'));
    } finally {
      if (weeklyReviewMountedRef.current) {
        setDeferredActionByTaskId((prev) => {
          const next = { ...prev };
          delete next[task.id];
          return next;
        });
      }
    }
  };

  const completeTask = async (task: Task) => {
    if (inlineActionByTaskId[task.id]) return;
    setInlineActionByTaskId((prev) => ({ ...prev, [task.id]: 'complete' }));
    try {
      await updateTask(task.id, { status: 'completed' });
      toast.success(format('review.taskCompletedNamed', { title: task.title }));
      invalidateTaskWorkspaceQueries(queryClient);
    } catch (error) {
      reportClientError('weeklyReview.completeTask', 'Failed to complete task', error, task.id);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (weeklyReviewMountedRef.current) {
        setInlineActionByTaskId((prev) => {
          const next = { ...prev };
          delete next[task.id];
          return next;
        });
      }
    }
  };

  const cancelTask = async (task: Task) => {
    if (inlineActionByTaskId[task.id]) return;
    setInlineActionByTaskId((prev) => ({ ...prev, [task.id]: 'cancel' }));
    try {
      await updateTask(task.id, { status: 'cancelled' });
      toast.success(format('review.taskCancelledNamed', { title: task.title }));
      invalidateTaskWorkspaceQueries(queryClient);
    } catch (error) {
      reportClientError('weeklyReview.cancelTask', 'Failed to cancel task', error, task.id);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (weeklyReviewMountedRef.current) {
        setInlineActionByTaskId((prev) => {
          const next = { ...prev };
          delete next[task.id];
          return next;
        });
      }
    }
  };

  return {
    dayContext,
    shelvingListId,
    shelveList,
    deferredActionByTaskId,
    isError,
    isLoading,
    locale,
    onOpenList,
    onSelectTask,
    refetch: () => { void refetch(); },
    review,
    runDeferredIntervention,
    t,
    // New enriched data
    completionsByDay,
    overdueBySeverity,
    upcomingNextWeek,
    nextWeekEvents,
    habits,
    completedLastWeek,
    totalFocusMinutes,
    habitsCompletionRate,
    inlineActionByTaskId,
    completeTask,
    cancelTask,
  };
}
