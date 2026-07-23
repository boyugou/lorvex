import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useMounted } from '@/lib/useMounted';

import { reportClientError } from '@/lib/errors/errorLogging';
import { truncateGraphemes } from '@/lib/textTruncate';
import { isTaskInRelativeSections } from '@/lib/tasks/dayBuckets';
import { getEventsByDateRange } from '@/lib/ipc/calendar';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { CurrentFocusWithTasks, Overview } from '@/lib/ipc/tasks/models';
import { getCurrentFocus, getOverview } from '@/lib/ipc/tasks/reviews';
import type { PopoverSummaryState, UsePopoverSummaryArgs } from './types';
import { TASK_STATUS } from '@lorvex/shared/types';

export function usePopoverSummary({
  dayContext,
  t,
}: UsePopoverSummaryArgs): PopoverSummaryState {
  const [overview, setOverview] = useState<Overview | null>(null);
  const [currentFocus, setCurrentFocus] = useState<CurrentFocusWithTasks | null>(null);
  const [todayEvents, setTodayEvents] = useState<UnifiedCalendarEvent[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [completingTaskIds, setCompletingTaskIds] = useState<string[]>([]);
  const [deferringTaskIds, setDeferringTaskIds] = useState<string[]>([]);
  const loadSummaryRequestIdRef = useRef(0);
  const popoverMountedRef = useMounted();

  useEffect(() => {
    return () => {
      loadSummaryRequestIdRef.current += 1;
    };
  }, []);

  const loadSummary = useCallback(async (withLoadingState = false) => {
    const requestId = loadSummaryRequestIdRef.current + 1;
    loadSummaryRequestIdRef.current = requestId;
    if (withLoadingState) setIsLoading(true);

    const [overviewResult, currentFocusResult, eventsResult] = await Promise.allSettled([
      getOverview(),
      getCurrentFocus(),
      getEventsByDateRange(dayContext.todayYmd, dayContext.todayYmd),
    ]);

    if (!popoverMountedRef.current || requestId !== loadSummaryRequestIdRef.current) return;

    if (overviewResult.status === 'fulfilled') {
      setOverview(overviewResult.value);
    } else {
      reportClientError('popover.loadOverview', 'Failed to load popover overview', overviewResult.reason);
    }

    if (currentFocusResult.status === 'fulfilled') {
      setCurrentFocus(currentFocusResult.value);
    } else {
      reportClientError('popover.loadCurrentFocus', 'Failed to load popover current focus', currentFocusResult.reason);
    }

    if (eventsResult.status === 'fulfilled') {
      setTodayEvents(eventsResult.value);
    } else {
      reportClientError('popover.loadTodayEvents', 'Failed to load popover calendar events', eventsResult.reason);
    }

    setIsLoading(false);
    // popoverMountedRef is a stable MutableRefObject from useMounted.
  }, [dayContext.todayYmd, popoverMountedRef]);

  useEffect(() => {
    void loadSummary(true);
  }, [loadSummary]);

  const planCount = currentFocus
    ? currentFocus.tasks.filter((task) => task.status === TASK_STATUS.open).length
    : overview?.current_focus?.task_count ?? 0;
  const attentionCount = overview?.stats.attention_count ?? 0;
  const overdueCount = overview?.stats.overdue_count ?? 0;
  // Memoize both halves so the `nextUpTasks` reference identity only
  // changes when the underlying data does — `handleOpenMain` in the
  // sibling actions controller takes `nextUpTasks` as a useCallback
  // dep, so a fresh array literal on every render would tear down
  // and rebuild the callback on every popover tick.
  const openPlanTasks = useMemo(
    () => (currentFocus?.tasks ?? []).filter((task) => task.status === TASK_STATUS.open).slice(0, 4),
    [currentFocus],
  );
  const openTodayTasks = useMemo(() => (
    (overview?.top_by_priority ?? [])
      .filter((task) => task.status === TASK_STATUS.open)
      .filter((task) => isTaskInRelativeSections(task, dayContext.todayYmd, ['overdue', 'today']))
      .slice(0, 4)
  ), [dayContext.todayYmd, overview]);
  const nextUpTasks = useMemo(
    () => (openPlanTasks.length > 0 ? openPlanTasks : openTodayTasks),
    [openPlanTasks, openTodayTasks],
  );

  const briefing = useMemo(() => {
    const raw = currentFocus?.briefing?.trim();
    if (!raw) return t('popover.noPlan');
    const firstLine = raw
      .split('\n')
      .map((line) => line.trim())
      .find((line) => line.length > 0);
    return truncateGraphemes(firstLine ?? raw, 160, false);
  }, [currentFocus, t]);

  return {
    briefing,
    completingTaskIds,
    isLoading,
    loadSummary,
    nextUpTasks,
    overdueCount,
    planCount,
    popoverMountedRef,
    setCompletingTaskIds,
    setDeferringTaskIds,
    deferringTaskIds,
    attentionCount,
    todayEvents,
  };
}
