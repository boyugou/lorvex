import { keepPreviousData, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useMemo, useRef, useState } from 'react';
import { getCalendarEventsUnified } from '@/lib/ipc/calendar';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { setPreference } from '@/lib/ipc/settings';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import type { ListWithCount, Task } from '@/lib/ipc/tasks/models';
import { getTasksByDateRange } from '@/lib/ipc/tasks/queries';
import { PREF_CALENDAR_VIEW_MODE, PREF_WEEK_STARTS_ON } from '@/lib/preferences/keys';
import { applyTaskFilters, useTaskFilters } from '@/lib/tasks/useTaskFilters';
import { QUERY_KEYS, invalidateCalendarViewQueries, invalidatePreferenceQueries } from '@/lib/query/queryKeys';
import { setPreferenceQueryData } from '@/lib/query/preferenceCache';
import { usePreference } from '@/lib/query/usePreference';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { STALE_SHORT, STALE_DEFAULT, STALE_LONG } from '@/lib/query/timing';
import { useI18n } from '@/lib/i18n';
import {
  formatCalendarDate,
  formatDate,
  localizedWeekdayOptions,
  localeWeekStartDay,
  parseWeekStartDayPreference,
} from '@/lib/dates/dateLocale';
import {
  addDays,
  daysInMonth,
  resolveWeekStartAnchor,
  toDateStr,
  weekAnchor,
} from './calendarViewUtils';
import {
  serializeCalendarViewModePreference,
  syncCalendarViewModePreference,
  type CalendarViewMode as ViewMode,
} from './viewModePreference.logic';

function resolveWeekdayLabels(locale: string, weekStartDay: number): string[] {
  return localizedWeekdayOptions(locale, weekStartDay).map((option) => option.label);
}

export function useCalendarViewController() {
  const { t, locale } = useI18n();
  const queryClient = useQueryClient();
  const dayContext = useConfiguredDayContext();
  const today = dayContext.todayYmd;
  const _todayParts = today.split('-').map(Number);
  const todayY = _todayParts[0] ?? 2024;
  const todayM = _todayParts[1] ?? 1;

  const { value: weekStartDay } = usePreference(
    PREF_WEEK_STARTS_ON,
    (raw) => parseWeekStartDayPreference(raw, localeWeekStartDay()),
    { staleTime: STALE_LONG },
  );

  const { value: viewModePref } = usePreference(
    PREF_CALENDAR_VIEW_MODE,
    (raw) => raw,
    { staleTime: Infinity },
  );
  const [viewMode, setViewMode] = useState<ViewMode>('month');
  const pendingViewModeWrite = useRef<ViewMode | null>(null);
  const pendingViewModeWriteSettled = useRef(false);
  useEffect(() => {
    setViewMode((current) => {
      const synced = syncCalendarViewModePreference({
        currentMode: current,
        rawPreference: viewModePref ?? null,
        pendingLocalWrite: pendingViewModeWrite.current,
        pendingLocalWriteSettled: pendingViewModeWriteSettled.current,
      });
      pendingViewModeWrite.current = synced.nextPendingLocalWrite;
      pendingViewModeWriteSettled.current = synced.nextPendingLocalWriteSettled;
      return synced.nextMode;
    });
  }, [viewModePref]);
  const [year, setYear] = useState(todayY);
  const [month, setMonth] = useState(todayM - 1);
  const [weekStart, setWeekStart] = useState(() => resolveWeekStartAnchor(today, today, weekStartDay));
  const [selectedDate, setSelectedDate] = useState<string | null>(today);
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);
  // Day panel collapse state. Defaults to closed so the calendar opens
  // on a clean grid; the panel slides in only after the user picks a
  // specific day. `selectedDate` continues to drive grid highlighting
  // independent of panel visibility, so today / the user's last pick
  // stays accented even while the panel is closed.
  const [dayPanelExpanded, setDayPanelExpanded] = useState(false);

  // Re-anchor week start when the preference changes.
  // Sentinel -1 ensures the effect fires on first resolved preference.
  const prevWeekStartDay = useRef(-1);
  useEffect(() => {
    if (prevWeekStartDay.current !== weekStartDay) {
      prevWeekStartDay.current = weekStartDay;
      setWeekStart(resolveWeekStartAnchor(selectedDate, today, weekStartDay));
    }
  }, [selectedDate, today, weekStartDay]);

  const from = viewMode === 'month'
    ? toDateStr(year, month, 1)
    : weekStart;
  const to = viewMode === 'month'
    ? toDateStr(year, month, daysInMonth(year, month))
    : addDays(weekStart, 6);

  const {
    data: tasks = [],
    isLoading: isTasksLoading,
    isError: isTasksError,
    refetch: refetchTasks,
  } = useQuery({
    queryKey: QUERY_KEYS.calendarTasks(from, to),
    queryFn: ({ signal }) => getTasksByDateRange(from, to, undefined, signal),
    staleTime: STALE_SHORT,
    placeholderData: keepPreviousData,
  });

  const {
    data: events = [],
    isLoading: isEventsLoading,
    isError: isEventsError,
    refetch: refetchEvents,
  } = useQuery({
    queryKey: QUERY_KEYS.calendarEvents(from, to),
    queryFn: ({ signal }) => getCalendarEventsUnified(from, to, signal),
    staleTime: STALE_SHORT,
    placeholderData: keepPreviousData,
  });

  const { data: lists = [] } = useQuery<ListWithCount[]>({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
  });

  const isCalendarLoading = isTasksLoading || isEventsLoading;
  const hasCalendarError = isTasksError || isEventsError;

  const { filterListId, setFilterListId, selectedTags, toggleTag, clearTagFilter, allTags } = useTaskFilters(tasks);

  const filteredTasks = useMemo(
    () => (selectedTags.size === 0 && !filterListId)
      ? tasks
      : applyTaskFilters(tasks, { listId: filterListId, tags: selectedTags }),
    [tasks, selectedTags, filterListId],
  );

  const tasksByDate = useMemo(() => {
    const map: Record<string, Task[]> = {};
    for (const task of filteredTasks) {
      const effectiveDate = task.planned_date ?? task.due_date;
      if (!effectiveDate) continue;
      if (!map[effectiveDate]) map[effectiveDate] = [];
      map[effectiveDate]!.push(task);
    }
    return map;
  }, [filteredTasks]);

  const eventsByDate = useMemo(() => {
    const map: Record<string, UnifiedCalendarEvent[]> = {};
    const seen = new Set<string>();
    for (const event of events) {
      if (!event.start_date) continue;
      const endDate = event.end_date || event.start_date;
      let current = event.start_date;
      while (current <= endDate) {
        const key = `${current}-${event.id}`;
        if (!seen.has(key)) {
          seen.add(key);
          if (!map[current]) map[current] = [];
          map[current]!.push(event);
        }
        current = addDays(current, 1);
      }
    }
    return map;
  }, [events]);

  const selectedTasks = selectedDate ? (tasksByDate[selectedDate] ?? []) : [];
  const selectedEvents = selectedDate ? (eventsByDate[selectedDate] ?? []) : [];

  const goToPrevMonth = () => {
    const nextYear = month === 0 ? year - 1 : year;
    const nextMonth = month === 0 ? 11 : month - 1;
    setYear(nextYear);
    setMonth(nextMonth);
    setSelectedDate(toDateStr(nextYear, nextMonth, 1));
  };

  const goToNextMonth = () => {
    const nextYear = month === 11 ? year + 1 : year;
    const nextMonth = month === 11 ? 0 : month + 1;
    setYear(nextYear);
    setMonth(nextMonth);
    setSelectedDate(toDateStr(nextYear, nextMonth, 1));
  };

  const goToPrevWeek = () => {
    setWeekStart((current) => addDays(current, -7));
    setSelectedDate((current) => current ? addDays(current, -7) : current);
  };
  const goToNextWeek = () => {
    setWeekStart((current) => addDays(current, 7));
    setSelectedDate((current) => current ? addDays(current, 7) : current);
  };

  const goToToday = () => {
    const _goTodayParts = dayContext.todayYmd.split('-').map(Number);
    setYear(_goTodayParts[0] ?? 2024);
    setMonth((_goTodayParts[1] ?? 1) - 1);
    setWeekStart(weekAnchor(dayContext.todayYmd, weekStartDay));
    setSelectedDate(dayContext.todayYmd);
    setSelectedTaskId(null);
  };

  const handleSelectDate = (dateStr: string) => {
    setSelectedDate(dateStr);
    setSelectedTaskId(null);
    // Picking a day always opens the panel. Closing happens via the
    // panel's own dismiss button so a stray re-click of the same date
    // doesn't toggle the panel away from the user's selection.
    setDayPanelExpanded(true);
  };

  const closeDayPanel = () => {
    setDayPanelExpanded(false);
  };

  const toggleDayPanel = () => {
    setDayPanelExpanded((prev) => !prev);
  };

  const switchViewMode = (mode: ViewMode) => {
    if (mode === viewMode) return;
    if (mode === 'week') {
      const anchor = selectedDate ?? toDateStr(year, month, 1);
      setWeekStart(weekAnchor(anchor, weekStartDay));
    } else {
      const date = new Date(`${weekStart}T00:00:00Z`);
      setYear(date.getUTCFullYear());
      setMonth(date.getUTCMonth());
    }
    pendingViewModeWrite.current = mode;
    pendingViewModeWriteSettled.current = false;
    setViewMode(mode);
    setSelectedTaskId(null);
    setPreferenceQueryData(
      queryClient,
      PREF_CALENDAR_VIEW_MODE,
      serializeCalendarViewModePreference(mode),
    );
    void setPreference(PREF_CALENDAR_VIEW_MODE, mode).then(() => {
      pendingViewModeWriteSettled.current = true;
      invalidatePreferenceQueries(queryClient, { key: PREF_CALENDAR_VIEW_MODE });
    }).catch(() => {
      pendingViewModeWrite.current = null;
      pendingViewModeWriteSettled.current = false;
      invalidatePreferenceQueries(queryClient, { key: PREF_CALENDAR_VIEW_MODE });
    });
  };

  // Calendar header labels — `formatDate` for the programmatic month-
  // start `Date.UTC(year, month, 1)` and `formatCalendarDate` for the
  // YMD-anchored week-boundary strings. All three calls share the
  // memoized formatter cache in `lib/dateLocale`, so navigating between
  // months / weeks reuses one `Intl.DateTimeFormat` instance per
  // (locale, options-shape) pair across the whole calendar surface.
  const monthLabel = formatDate(new Date(Date.UTC(year, month, 1)), locale, {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  });

  const weekEndStr = addDays(weekStart, 6);
  const weekLabel = (() => {
    const startFmt = formatCalendarDate(weekStart, locale, {
      month: 'short',
      day: 'numeric',
    });
    const endFmt = formatCalendarDate(weekEndStr, locale, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
    return `${startFmt} – ${endFmt}`;
  })();
  const weekdayLabels = resolveWeekdayLabels(locale, weekStartDay);

  const invalidateAll = () => {
    invalidateCalendarViewQueries(queryClient);
  };

  return {
    allTags,
    clearTagFilter,
    dateRangeFrom: from,
    dateRangeTo: to,
    eventsByDate,
    filterListId,
    goToNextMonth,
    goToNextWeek,
    goToPrevMonth,
    goToPrevWeek,
    goToToday,
    handleSelectDate,
    dayPanelExpanded,
    closeDayPanel,
    toggleDayPanel,
    hasCalendarError,
    invalidateAll,
    isCalendarLoading,
    lists,
    locale,
    month,
    monthLabel,
    refetchEvents,
    refetchTasks,
    selectedDate,
    selectedEvents,
    selectedTags,
    selectedTaskId,
    setFilterListId,
    selectedTasks,
    setSelectedTaskId,
    switchViewMode,
    t,
    tasksByDate,
    today,
    toggleTag,
    viewMode,
    weekLabel,
    weekStart,
    weekdayLabels,
    weekStartDay,
    year,
  };
}

export type CalendarViewController = ReturnType<typeof useCalendarViewController>;
