import { useMemo } from 'react';
import { keepPreviousData, useQuery } from '@tanstack/react-query';

import { reportClientError } from '@/lib/errors/errorLogging';
import { resolveDateLocale } from '@/lib/dates/dateLocale';
import { useI18n } from '@/lib/i18n';
import { useCurrentTime } from '@/lib/time/useCurrentTime';
import { getEventsByDateRange } from '@/lib/ipc/calendar';
import { getDashboardLayout } from '@/lib/ipc/dashboard';
import { getSetupStatus } from '@/lib/ipc/settings';
import { getOverdueTasks, getSomedayTasks, getTodayPoolTasks, getUpcomingTasks } from '@/lib/ipc/tasks/queries';
import { getCurrentFocus, getFocusSchedule } from '@/lib/ipc/tasks/reviews';
import { DAY_SCOPED_QUERY_KEYS, UPCOMING_TASKS_WINDOW_DAYS } from '@/lib/query/dayScopedQueryKeys';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT, REFETCH_INTERVAL } from '@/lib/query/timing';
import { compareTaskByDueThenPriority, compareTaskByPriorityThenDue } from '@/lib/tasks/taskComparators';
import type {
  TodayViewContentProps,
  UseTodayViewControllerArgs,
} from './types';
import { resolveTodayGreetingKey } from './greeting';
import { TASK_STATUS } from '@lorvex/shared/types';

export function useTodayViewController({
  dayContext,
  usesMobileLayout,
  onSelectTask,
  overview,
}: UseTodayViewControllerArgs): TodayViewContentProps {
  const { t, locale } = useI18n();

  const todayIso = dayContext.todayYmd;
  // memoize the day-label formatter so re-renders driven
  // by subscribed-query refetches don't reconstruct an
  // Intl.DateTimeFormat (~0.5-2 ms each on V8) on every tick.
  // TodayView re-renders on every mutation broadcast + every
  // REFETCH_INTERVAL, so this was ~1-3 ms of avoidable per-render
  // cost.
  const today = useMemo(() => {
    const [ty = 2024, tm = 1, td = 1] = todayIso.split('-').map(Number);
    const todayRefDate = new Date(Date.UTC(ty, tm - 1, td, 12));
    return new Intl.DateTimeFormat(resolveDateLocale(locale), {
      weekday: 'long',
      month: 'long',
      day: 'numeric',
      timeZone: dayContext.timezone,
    }).format(todayRefDate);
  }, [todayIso, locale, dayContext.timezone]);

  const currentTime = useCurrentTime(dayContext.timezone);
  const greeting = t(resolveTodayGreetingKey(currentTime));

  const {
    data: plan,
    isLoading: isPlanLoading,
    isError: isPlanError,
    refetch: refetchPlan,
  } = useQuery({
    queryKey: QUERY_KEYS.currentFocus(),
    queryFn: ({ signal }) => getCurrentFocus(signal),
    refetchInterval: REFETCH_INTERVAL,
  });

  const {
    data: layout,
    isLoading: isLayoutLoading,
    isError: isLayoutError,
    refetch: refetchLayout,
  } = useQuery({
    queryKey: QUERY_KEYS.dashboardLayout(),
    queryFn: ({ signal }) => getDashboardLayout(signal),
    staleTime: STALE_DEFAULT,
    refetchInterval: REFETCH_INTERVAL,
  });
  const overdueCount = overview?.stats?.overdue_count ?? 0;
  const shouldLoadOverdueTasks = overdueCount > 0;
  const todayPoolCount = overview?.stats?.today_pool_count ?? 0;

  const {
    data: overdueTasks = [],
    isLoading: isOverdueTasksLoading,
    isError: isOverdueTasksError,
    refetch: refetchOverdueTasks,
  } = useQuery({
    queryKey: QUERY_KEYS.todayOverdueTasks(),
    queryFn: ({ signal }) => getOverdueTasks(signal),
    enabled: shouldLoadOverdueTasks,
    refetchInterval: shouldLoadOverdueTasks ? REFETCH_INTERVAL : false,
    placeholderData: keepPreviousData,
  });

  const {
    data: todayPoolTasks = [],
    isLoading: isTodayPoolTasksLoading,
    isError: isTodayPoolTasksError,
    refetch: refetchTodayPoolTasks,
  } = useQuery({
    queryKey: QUERY_KEYS.todayPoolTasks(),
    queryFn: ({ signal }) => getTodayPoolTasks(signal),
    enabled: todayPoolCount > 0,
    refetchInterval: todayPoolCount > 0 ? REFETCH_INTERVAL : false,
    placeholderData: keepPreviousData,
  });
  const sortedOverdueTasks = useMemo(
    () => overdueTasks.slice().sort(compareTaskByDueThenPriority),
    [overdueTasks],
  );

  const focusTaskIds = useMemo(() => {
    if (!plan?.tasks) return new Set<string>();
    return new Set(plan.tasks.filter((task) => task.status === TASK_STATUS.open).map((task) => task.id));
  }, [plan?.tasks]);

  const filteredTodayPoolTasks = useMemo(
    () => todayPoolTasks
      .filter((task) => !focusTaskIds.has(task.id))
      .sort(compareTaskByPriorityThenDue),
    [focusTaskIds, todayPoolTasks],
  );

  const hasScheduleSection = layout?.sections.some((section) => section.type === 'schedule') ?? false;
  const {
    data: focusSchedule,
    isError: isScheduleError,
    refetch: refetchSchedule,
  } = useQuery({
    queryKey: QUERY_KEYS.focusSchedule(),
    queryFn: ({ signal }) => getFocusSchedule(signal),
    enabled: hasScheduleSection,
    refetchInterval: hasScheduleSection ? REFETCH_INTERVAL : false,
  });

  const hasSomedayPeek = layout?.sections.some((section) => section.type === 'someday_peek') ?? false;
  const {
    data: somedayTasks = [],
    isError: isSomedayError,
    refetch: refetchSomeday,
  } = useQuery({
    queryKey: QUERY_KEYS.somedayTasks(),
    queryFn: ({ signal }) => getSomedayTasks(signal),
    enabled: hasSomedayPeek,
    refetchInterval: hasSomedayPeek ? REFETCH_INTERVAL : false,
    placeholderData: keepPreviousData,
  });

  const hasUpcomingWeek = layout?.sections.some((section) => section.type === 'upcoming_week') ?? false;
  const {
    data: upcomingWeekTasksRaw = [],
    isError: isUpcomingWeekError,
    refetch: refetchUpcomingWeek,
  } = useQuery({
    queryKey: DAY_SCOPED_QUERY_KEYS.upcomingWeekTasks(todayIso),
    queryFn: ({ signal }) => getUpcomingTasks(UPCOMING_TASKS_WINDOW_DAYS, signal),
    enabled: hasUpcomingWeek,
    refetchInterval: hasUpcomingWeek ? REFETCH_INTERVAL : false,
    placeholderData: keepPreviousData,
  });
  const upcomingWeekTasks = useMemo(() => {
    if (!hasUpcomingWeek) return [];
    return upcomingWeekTasksRaw.filter((task) => !focusTaskIds.has(task.id));
  }, [focusTaskIds, hasUpcomingWeek, upcomingWeekTasksRaw]);

  const {
    data: todayEvents = [],
    isError: isTodayEventsError,
    refetch: refetchTodayEvents,
  } = useQuery({
    queryKey: QUERY_KEYS.todayEvents(todayIso),
    queryFn: ({ signal }) => getEventsByDateRange(todayIso, todayIso, signal),
    staleTime: STALE_DEFAULT,
    refetchInterval: REFETCH_INTERVAL,
  });

  const { data: setupStatus } = useQuery({
    queryKey: QUERY_KEYS.setupStatus(),
    queryFn: ({ signal }) => getSetupStatus(signal),
    staleTime: Infinity,
    refetchInterval: false,
  });

  const stats = overview?.stats;
  // Stabilize the section list reference so downstream `useMemo`s
  // keyed on `sections` (e.g. focusSection / nonFocusSections) don't
  // invalidate every refetch tick. The 9 Today queries refetch every
  // 60s; `layout?.sections` is identical-by-reference across those
  // ticks, so the filter result should be too.
  const sections = useMemo(
    () =>
      (layout?.sections ?? []).filter(
        (section) => !(usesMobileLayout && section.type === 'schedule'),
      ),
    [layout?.sections, usesMobileLayout],
  );
  const hasPlanTasks = (plan?.tasks?.length ?? 0) > 0;
  const isAiLayout = Boolean(layout?.updated_by && layout.updated_by !== 'human');
  const isTodayLoading =
    isPlanLoading
    || isLayoutLoading
    || (shouldLoadOverdueTasks && isOverdueTasksLoading)
    || (todayPoolCount > 0 && isTodayPoolTasksLoading);
  const hasRecoverableTodayError =
    isPlanError ||
    isLayoutError ||
    (shouldLoadOverdueTasks && isOverdueTasksError) ||
    (todayPoolCount > 0 && isTodayPoolTasksError) ||
    isTodayEventsError ||
    (hasScheduleSection && isScheduleError) ||
    (hasSomedayPeek && isSomedayError) ||
    (hasUpcomingWeek && isUpcomingWeekError);

  const refetchFailedTodayQueries = () => {
    const retries: Array<Promise<unknown>> = [];
    if (isPlanError) retries.push(refetchPlan());
    if (isLayoutError) retries.push(refetchLayout());
    if (shouldLoadOverdueTasks && isOverdueTasksError) retries.push(refetchOverdueTasks());
    if (todayPoolCount > 0 && isTodayPoolTasksError) retries.push(refetchTodayPoolTasks());
    if (isTodayEventsError) retries.push(refetchTodayEvents());
    if (hasScheduleSection && isScheduleError) retries.push(refetchSchedule());
    if (hasSomedayPeek && isSomedayError) retries.push(refetchSomeday());
    if (hasUpcomingWeek && isUpcomingWeekError) retries.push(refetchUpcomingWeek());
    if (retries.length === 0) return;
    void Promise.allSettled(retries).then((results) => {
      const rejected = results.filter(
        (result): result is PromiseRejectedResult => result.status === 'rejected',
      );
      if (rejected.length === 0) return;
      reportClientError(
        'today.retryLoad',
        'Today retry failed to refresh one or more queries',
        rejected[0]!.reason,
        `rejected=${rejected.length}`,
        'warn',
      );
    });
  };

  return {
    todayPoolTasks: filteredTodayPoolTasks,
    greeting,
    hasPlanTasks,
    hasRecoverableTodayError,
    isAiLayout,
    isFirstRun: setupStatus?.setup_completed === false,
    isTodayLoading,
    onSelectTask,
    overdueTasks: sortedOverdueTasks,
    overview,
    plan,
    refetchFailedTodayQueries,
    focusSchedule: focusSchedule ?? null,
    sections,
    somedayTasks,
    stats,
    t,
    today,
    todayIso,
    todayEvents,
    upcomingWeekTasks,
  };
}
