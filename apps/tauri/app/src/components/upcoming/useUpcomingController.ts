import { useCallback, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getEventsByDateRange } from '@/lib/ipc/calendar';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import type { Task } from '@/lib/ipc/tasks/models';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { getUpcomingTasks } from '@/lib/ipc/tasks/queries';
import { formatDueDate } from '@/lib/format';
import { applyTaskFilters, useTaskFilters } from '@/lib/tasks/useTaskFilters';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useBulkActions } from '@/lib/tasks/useBulkActions';
import { DAY_SCOPED_QUERY_KEYS, UPCOMING_TASKS_WINDOW_DAYS } from '@/lib/query/dayScopedQueryKeys';
import {
  applyOptimisticTaskPatch,
  rollbackOptimisticTaskPatch,
} from '@/lib/query/optimisticEntity';
import { QUERY_KEYS, invalidateTaskMutationQueries } from '@/lib/query/queryKeys';
import { toast } from '@/lib/notifications/toast';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import { useTaskSelection } from '@/lib/tasks/useTaskSelection';
import { computeDateRange, computeWeekDates, sortEvents } from './dateUtils';
import { sortTasks } from '@/lib/tasks/taskSorting';
import type { SortKey } from '../all-tasks/types';
import { useI18n } from '@/lib/i18n';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { useCurrentTime } from '@/lib/time/useCurrentTime';
import { useDebounced } from '@/lib/useDebounced';
import { useScrollRestore } from '@/lib/useScrollRestore';
import { useTaskListActions } from '@/lib/tasks/useTaskListActions';
import { useTaskListKeyboard } from '@/lib/tasks/useTaskListKeyboard';
import { taskEffectiveActionDate } from '@/lib/tasks/dayBuckets';
import { useCollapsibleSections } from '@/lib/useCollapsibleSections';
import {
  isOneOf,
  isString,
  useLocalStorageBackedState,
} from '@/lib/storage/useLocalStorageBackedState';
import {
  isPriorityOrNull,
  type PriorityFilterValue,
} from '@/lib/tasks/priorityFilter';

const PK = 'upcoming.';
const COLLAPSE_PK = PK + 'collapsed';
const TASK_FILTER_PERSISTENCE = {
  filterListIdKey: PK + 'filterListId',
  selectedTagsKey: PK + 'selectedTags',
} as const;
export const OVERDUE_KEY = '__overdue__';
export const DRAG_MIME = 'application/x-upcoming-task';

const VIEW_MODE_OPTIONS = ['list', 'timeline'] as const;
const SORT_KEY_OPTIONS: SortKey[] = ['default', 'priority', 'actionDate'];
const isViewMode = isOneOf(VIEW_MODE_OPTIONS);
const isSortKey = isOneOf(SORT_KEY_OPTIONS);

/** Sort keys relevant for UpcomingView — exclude 'dueDate' since tasks are already grouped by date. */
export const UPCOMING_SORT_KEYS: SortKey[] = ['default', 'priority', 'actionDate'];

export type ViewMode = 'list' | 'timeline';

interface UseUpcomingControllerOptions {
  onSelectTask?: ((taskId: string) => void) | undefined;
}

export function useUpcomingController({ onSelectTask }: UseUpcomingControllerOptions) {
  const { t, format, locale } = useI18n();
  const qc = useQueryClient();
  const dayContext = useConfiguredDayContext();
  const scroll = useScrollRestore('upcoming');
  // persist view-state per the per-view PK pattern so a
  // refresh keeps search / filter pills / view-mode / sort intact.
  const [viewMode, setViewMode] = useLocalStorageBackedState<ViewMode>(
    PK + 'viewMode',
    'list',
    isViewMode,
  );
  const [search, setSearch] = useLocalStorageBackedState<string>(PK + 'search', '', isString);
  const [filterPriority, setFilterPriority] = useLocalStorageBackedState<PriorityFilterValue>(
    PK + 'filterPriority',
    null,
    isPriorityOrNull,
  );
  const [sortKey, setSortKey] = useLocalStorageBackedState<SortKey>(
    PK + 'sortKey',
    'default',
    isSortKey,
  );
  const {
    collapsed: collapsedDates,
    toggle: toggleDateCollapse,
    collapseAll: collapseAllDates,
    expandAll: expandAllDates,
  } = useCollapsibleSections(COLLAPSE_PK);

  const [dragOverDate, setDragOverDate] = useState<string | null>(null);
  const nowHHMM = useCurrentTime(dayContext.timezone);
  const rescheduleInFlight = useRef(false);
  const dateRange = useMemo(() => computeDateRange(dayContext.todayYmd), [dayContext.todayYmd]);
  const weekDates = useMemo(() => computeWeekDates(dayContext.todayYmd), [dayContext.todayYmd]);

  // ---------------------------------------------------------------------------
  // Data fetching
  // ---------------------------------------------------------------------------

  const { data: tasks = [], isLoading: isTasksLoading, isError: isTasksError, refetch: refetchTasks } = useQuery({
    queryKey: DAY_SCOPED_QUERY_KEYS.upcomingTasks(dayContext.todayYmd),
    queryFn: ({ signal }) => getUpcomingTasks(UPCOMING_TASKS_WINDOW_DAYS, signal),
  });

  const { data: events = [], isError: isEventsError, refetch: refetchEvents } = useQuery({
    queryKey: QUERY_KEYS.upcomingEvents(dateRange.from, dateRange.to),
    queryFn: ({ signal }) => getEventsByDateRange(dateRange.from, dateRange.to, signal),
  });

  const { data: lists = [] } = useQuery({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
  });

  // ---------------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------------

  const {
    filterListId,
    setFilterListId,
    selectedTags,
    toggleTag,
    clearTagFilter,
    replaceSelectedTags,
    allTags,
  } = useTaskFilters(tasks, TASK_FILTER_PERSISTENCE);

  // Debounce the search box so filter recomputation + virtualizer
  // re-measure don't fire on every keystroke. Mirrors the canonical
  // pattern in `useAllTasksController` and the command palette.
  // 300 ms matches the AllTasks tuning.
  const debouncedSearch = useDebounced(search, 300);
  const filteredTasks = useMemo(
    () => applyTaskFilters(tasks, {
      listId: filterListId,
      priority: filterPriority,
      tags: selectedTags,
      search: debouncedSearch,
    }),
    [tasks, debouncedSearch, filterListId, filterPriority, selectedTags],
  );

  // ---------------------------------------------------------------------------
  // Grouping & sorting
  // ---------------------------------------------------------------------------

  const groupedTasks = useMemo(() => {
    const groups = filteredTasks.reduce<Record<string, Task[]>>((acc, task) => {
      const key = taskEffectiveActionDate(task) ?? 'no-date';
      if (!acc[key]) acc[key] = [];
      acc[key].push(task);
      return acc;
    }, {});
    if (sortKey !== 'default') {
      for (const key of Object.keys(groups)) {
        groups[key] = sortTasks(groups[key] ?? [], sortKey);
      }
    }
    return groups;
  }, [filteredTasks, sortKey]);

  const groupedEvents = useMemo(() => {
    return events.reduce<Record<string, UnifiedCalendarEvent[]>>((acc, event) => {
      const key = event.start_date;
      if (!acc[key]) acc[key] = [];
      acc[key].push(event);
      return acc;
    }, {});
  }, [events]);

  const allDates = useMemo(() => {
    const dateSet = new Set<string>(weekDates);
    for (const date of Object.keys(groupedTasks)) dateSet.add(date);
    for (const date of Object.keys(groupedEvents)) dateSet.add(date);
    return [...dateSet].sort();
  }, [weekDates, groupedTasks, groupedEvents]);

  const overdueDates = useMemo(
    () => allDates.filter((d) => d < dayContext.todayYmd),
    [allDates, dayContext.todayYmd],
  );

  const futureDates = useMemo(
    () => allDates.filter((d) => d >= dayContext.todayYmd),
    [allDates, dayContext.todayYmd],
  );

  const overdueTasks = useMemo(() => {
    const result: Task[] = [];
    for (const date of overdueDates) {
      result.push(...(groupedTasks[date] ?? []));
    }
    return sortKey !== 'default' ? sortTasks(result, sortKey) : result;
  }, [overdueDates, groupedTasks, sortKey]);

  const totalEstimatedMinutes = useMemo(
    () => filteredTasks.reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0),
    [filteredTasks],
  );

  const overdueMinutes = useMemo(
    () => overdueTasks.reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0),
    [overdueTasks],
  );

  const isEmpty = filteredTasks.length === 0 && events.length === 0;
  const isFilterActive = !!(search.trim() || filterListId || filterPriority !== null || selectedTags.size > 0);

  // ---------------------------------------------------------------------------
  // Copy week plan
  // ---------------------------------------------------------------------------

  const { copy, copying } = useCopyToClipboard();
  const handleCopyWeekPlan = useCallback(async () => {
    if (copying) return;
    const lines: string[] = [`${t('upcoming.title')} (${dateRange.from} → ${dateRange.to})\n`];
    for (const date of allDates) {
      const dayTasks = groupedTasks[date] ?? [];
      const dayEvents = sortEvents(groupedEvents[date] ?? []);
      if (dayTasks.length === 0 && dayEvents.length === 0) continue;
      const label = formatDueDate(date, { dayContext, locale, todayLabel: t('upcoming.today'), tomorrowLabel: t('upcoming.tomorrow'), yesterdayLabel: t('upcoming.yesterday') });
      lines.push(`${label} (${date}):`);
      for (const event of dayEvents) {
        const time = event.all_day ? t('calendar.eventAllDay') : event.start_time ?? '';
        lines.push(`  ${time} ${event.title}`);
      }
      for (const task of dayTasks) {
        const dur = task.estimated_minutes ? ` (${task.estimated_minutes}${t('common.min')})` : '';
        const pri = task.priority && task.priority <= 2 ? ` P${task.priority}` : '';
        lines.push(`  - [ ] ${task.title}${dur}${pri}`);
      }
      lines.push('');
    }
    await copy(lines.join('\n').trimEnd(), t('upcoming.weekPlanCopied'));
  }, [allDates, copy, copying, dateRange, dayContext, groupedEvents, groupedTasks, locale, t]);

  // ---------------------------------------------------------------------------
  // Keyboard navigation task IDs
  // ---------------------------------------------------------------------------

  const allTaskIds = useMemo(() => {
    const overdueIds = collapsedDates.has(OVERDUE_KEY)
      ? []
      : overdueTasks.map((tk) => tk.id);
    const futureIds = futureDates.flatMap((date) =>
      collapsedDates.has(date) ? [] : (groupedTasks[date] ?? []).map((tk) => tk.id),
    );
    return [...overdueIds, ...futureIds];
  }, [collapsedDates, futureDates, groupedTasks, overdueTasks]);
  const allTaskIdSet = useMemo(() => new Set(allTaskIds), [allTaskIds]);

  const allCollapsibleKeys = useMemo(
    () => (overdueTasks.length > 0 ? [OVERDUE_KEY, ...futureDates] : futureDates),
    [overdueTasks.length, futureDates],
  );

  // ---------------------------------------------------------------------------
  // Selection + bulk actions
  // ---------------------------------------------------------------------------

  const {
    selectionMode,
    selectedIds,
    selectAll,
    toggleTaskSelected,
    setSelectionModeEnabled,
    setSelectedIds,
    clearSelection,
    handleClickWithModifiers,
    handleKeyboardExtend,
  } = useTaskSelection(allTaskIdSet, null, {
    // localized "selection collapsed" warning toast.
    onSelectionCollapsedMessage: (count) =>
      format('allTasks.selectionCollapsed', { count: String(count) }),
    onSelectionCollapsedUndoLabel: () => t('allTasks.selectionCollapsedRestore'),
  });
  const bulk = useBulkActions({
    tasks: filteredTasks,
    selectedIds,
    setSelectedIds,
    deferDateYmd: dayContext.tomorrowYmd,
  });

  const onExtendSelection = useCallback(
    (direction: 'up' | 'down', focusedId: string | null) =>
      handleKeyboardExtend(direction, allTaskIds, focusedId),
    [handleKeyboardExtend, allTaskIds],
  );
  const onClickWithModifiers = useCallback(
    (id: string, event: ReactMouseEvent<HTMLButtonElement>) =>
      handleClickWithModifiers(id, event, allTaskIds, null),
    [handleClickWithModifiers, allTaskIds],
  );

  const baseActions = useTaskListActions(filteredTasks);
  const actions = {
    ...baseActions,
    onToggleSelected: toggleTaskSelected,
    setSelectionModeEnabled,
    selectionModeActive: selectionMode,
    onExtendSelection,
    onSelectAll: selectAll,
    onClearSelection: clearSelection,
    hasSelection: selectedIds.size > 0,
  };
  const keyboard = useTaskListKeyboard({
    taskIds: allTaskIds,
    onSelect: onSelectTask,
    actions,
    disabled: isTasksLoading || viewMode === 'timeline',
  });

  // ---------------------------------------------------------------------------
  // Drag-and-drop reschedule
  // ---------------------------------------------------------------------------

  const handleRescheduleTask = useCallback(async (taskId: string, newDate: string) => {
    if (rescheduleInFlight.current) return;
    const task = tasks.find((tk) => tk.id === taskId);
    if (!task) return;

    // The view groups by the canonical effective action date.
    // Match the drag semantics to the visual grouping: if the task has a
    // planned_date, move planned_date; otherwise move due_date.
    const effectiveDate = taskEffectiveActionDate(task);
    if (effectiveDate === newDate) return;

    const updates = task.planned_date
      ? { planned_date: newDate }
      : { due_date: newDate };

    rescheduleInFlight.current = true;
    // mirror the calendar drag-reschedule pattern:
    // patch the task's planned/due date in every cached query before
    // the IPC round-trip so the pill stays anchored under the cursor
    // on its new day for the same paint as the drop. Without this the
    // pill snaps back to the source group for ~200 ms before the
    // refetch lands and re-buckets it. Snapshot → mutate → rollback
    // on error.
    //
    // when the new date falls outside every visible cached
    // query window (here: the 7-day upcoming window), the optimistic
    // patch alone leaves the task in its old visual slot with a stale
    // effective-date stamp until the refetch lands. Hand the helper a
    // predicate that splices the task out of any cache entry whose
    // window can no longer contain it, so the source group is empty
    // immediately on drop. Rollback re-inserts at the original index.
    const snapshot = await applyOptimisticTaskPatch(qc, taskId, updates, {
      removeFromCacheIf: (patched) => {
        const effective = taskEffectiveActionDate(patched);
        if (!effective) return false;
        // The 7-day upcoming window. We treat dates >= today + 7 as
        // "out of window"; overdue (< today) stays cached because the
        // overdue group is rendered from the same query.
        const windowEnd = computeDateRange(dayContext.todayYmd).to;
        return effective > windowEnd;
      },
    });
    try {
      await updateTask(taskId, updates);
      invalidateTaskMutationQueries(qc, { listId: task.list_id });
      toast.success(t('calendar.taskRescheduled'));
    } catch (error) {
      rollbackOptimisticTaskPatch(qc, snapshot);
      reportClientError('upcoming.reschedule', 'Failed to reschedule task', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      rescheduleInFlight.current = false;
    }
  }, [qc, t, tasks, dayContext.todayYmd]);

  return {
    // i18n + context
    t,
    locale,
    dayContext,
    qc,

    // scroll
    scroll,

    // view mode
    viewMode,
    setViewMode,

    // search / filter / sort
    search,
    setSearch,
    filterPriority,
    setFilterPriority,
    sortKey,
    setSortKey,
    filterListId,
    setFilterListId,
    selectedTags,
    toggleTag,
    clearTagFilter,
    replaceSelectedTags,
    allTags,

    // collapse state
    collapsedDates,
    toggleDateCollapse,
    collapseAllDates,
    expandAllDates,

    // drag state
    dragOverDate,
    setDragOverDate,

    // time
    nowHHMM,

    // date ranges
    dateRange,
    weekDates,

    // data
    tasks,
    events,
    lists,
    isTasksLoading,
    isTasksError,
    isEventsError,
    refetchTasks,
    refetchEvents,

    // derived data
    filteredTasks,
    groupedTasks,
    groupedEvents,
    allDates,
    overdueDates,
    futureDates,
    overdueTasks,
    totalEstimatedMinutes,
    overdueMinutes,
    isEmpty,
    isFilterActive,

    // copy
    copying,
    handleCopyWeekPlan,

    // keyboard nav
    allTaskIds,
    allCollapsibleKeys,
    keyboard,

    // selection + bulk
    selectionMode,
    selectedIds,
    selectAll,
    toggleTaskSelected,
    setSelectionModeEnabled,
    setSelectedIds,
    clearSelection,
    onClickWithModifiers,
    bulk,

    // actions + overlays
    actions,

    // reschedule
    handleRescheduleTask,
  } as const;
}
