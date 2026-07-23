import { useCallback, useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import type { Task } from '@/lib/ipc/tasks/models';
import { getAllTasks } from '@/lib/ipc/tasks/queries';
import { parseTags } from '@/lib/format';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { daysBetween } from '@/lib/timeUtils';
import { useI18n } from '@/lib/i18n';
import { toast } from '@/lib/notifications/toast';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import { useDebounced } from '@/lib/useDebounced';
import { useTaskFilters } from '@/lib/tasks/useTaskFilters';
import { useTaskListActions } from '@/lib/tasks/useTaskListActions';
import { useTaskListKeyboard } from '@/lib/tasks/useTaskListKeyboard';
import { compareTaskByPriorityThenDue } from '@/lib/tasks/taskComparators';
import { URGENT_DAYS_THRESHOLD, type QuadrantKey } from './quadrants';
import type { HorizonValue } from '../ui/TimeHorizonPicker';
import { useEisenhowerPriorityActions } from './useEisenhowerPriorityActions';
import {
  isString,
  useLocalStorageBackedState,
} from '@/lib/storage/useLocalStorageBackedState';
import {
  isPriorityOrNull,
  type PriorityFilterValue,
} from '@/lib/tasks/priorityFilter';
import { TASK_STATUS } from '@lorvex/shared/types';

const PK = 'eisenhower.';
const TASK_FILTER_PERSISTENCE = {
  filterListIdKey: PK + 'filterListId',
  selectedTagsKey: PK + 'selectedTags',
} as const;

function isHorizonValue(value: unknown): value is HorizonValue {
  return value === null || typeof value === 'number';
}

interface UseEisenhowerControllerOptions {
  onSelectTask?: ((taskId: string) => void) | undefined;
}

const IMPORTANT_QUADRANTS: QuadrantKey[] = ['urgent_important', 'not_urgent_important'];

export function useEisenhowerController({ onSelectTask }: UseEisenhowerControllerOptions) {
  const { t } = useI18n();
  const { todayYmd } = useConfiguredDayContext();
  const [dragOverQuadrant, setDragOverQuadrant] = useState<QuadrantKey | null>(null);
  // persist view-state per-view.
  const [search, setSearch] = useLocalStorageBackedState<string>(PK + 'search', '', isString);
  const [horizonDays, setHorizonDays] = useLocalStorageBackedState<HorizonValue>(
    PK + 'horizonDays',
    60,
    isHorizonValue,
  );
  const [filterPriority, setFilterPriority] = useLocalStorageBackedState<PriorityFilterValue>(
    PK + 'filterPriority',
    null,
    isPriorityOrNull,
  );

  // --------------- queries ---------------

  const {
    data: tasks = [],
    isLoading,
    isError,
    refetch,
  } = useQuery({
    queryKey: QUERY_KEYS.allTasks(false, false),
    queryFn: ({ signal }) => getAllTasks(false, false, signal),
  });

  const { data: lists = [] } = useQuery({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
  });

  const {
    filterListId,
    setFilterListId,
    selectedTags,
    toggleTag,
    clearTagFilter,
    replaceSelectedTags,
    allTags,
  } = useTaskFilters(tasks, TASK_FILTER_PERSISTENCE);

  // --------------- mutations ---------------

  const {
    handleChangePriority,
    handleChangeDueDate,
    isChangingPriority,
    isChangingDueDate,
  } = useEisenhowerPriorityActions({ t });

  const handleDrop = useCallback(
    (targetQuadrant: QuadrantKey, taskId: string) => {
      setDragOverQuadrant(null);
      const task = tasks.find((item) => item.id === taskId);
      if (!task) return;

      const isCurrentlyImportant = task.priority != null && task.priority <= 2;
      const isTargetImportant = IMPORTANT_QUADRANTS.includes(targetQuadrant);

      if (isCurrentlyImportant === isTargetImportant) {
        // Dragging between same-importance quadrants (e.g. urgent→not-urgent)
        // only changes the urgency axis, which is derived from due_date proximity
        // and cannot be changed by drag. Show feedback so the drop isn't silent.
        toast.info(t('eisenhower.sameImportance'));
        return;
      }

      const newPriority = isTargetImportant ? 2 : 3;

      handleChangePriority(taskId, newPriority);
    },
    [handleChangePriority, tasks, t],
  );

  // --------------- quadrant grouping ---------------

  // Debounce the search box so the four-quadrant grouping +
  // virtualizer re-measures don't fire on every keystroke. Mirrors
  // AllTasks / Upcoming / Kanban / Someday. 300 ms matches the
  // AllTasks tuning.
  const debouncedSearch = useDebounced(search, 300);

  const quadrants = useMemo(() => {
    const grouped: Record<QuadrantKey, Task[]> = {
      urgent_important: [],
      not_urgent_important: [],
      urgent_not_important: [],
      not_urgent_not_important: [],
    };

    const q = debouncedSearch.trim().toLowerCase();
    const activeTasks = tasks.filter((task) => {
      if (task.status !== TASK_STATUS.open) return false;
      if (filterListId && task.list_id !== filterListId) return false;
      if (filterPriority !== null && task.priority !== filterPriority) return false;
      if (selectedTags.size > 0) {
        const taskTags = parseTags(task.tags);
        if (!taskTags.some((tag) => selectedTags.has(tag))) return false;
      }
      if (q && !task.title.toLowerCase().includes(q) && !(task.body && task.body.toLowerCase().includes(q))) return false;
      // Exclude tasks beyond the selected time horizon
      if (horizonDays !== null && task.due_date) {
        if (daysBetween(todayYmd, task.due_date) > horizonDays) return false;
      }
      return true;
    });

    for (const task of activeTasks) {
      const isImportant = task.priority != null && task.priority <= 2;
      // Urgency = deadline proximity: overdue or due within URGENT_DAYS_THRESHOLD days
      const isUrgent = task.due_date != null && daysBetween(todayYmd, task.due_date) <= URGENT_DAYS_THRESHOLD;

      if (isUrgent && isImportant) {
        grouped.urgent_important.push(task);
      } else if (!isUrgent && isImportant) {
        grouped.not_urgent_important.push(task);
      } else if (isUrgent && !isImportant) {
        grouped.urgent_not_important.push(task);
      } else {
        grouped.not_urgent_not_important.push(task);
      }
    }

    const sortTasks = (items: Task[]) => items.sort(compareTaskByPriorityThenDue);

    return {
      urgent_important: sortTasks(grouped.urgent_important),
      not_urgent_important: sortTasks(grouped.not_urgent_important),
      urgent_not_important: sortTasks(grouped.urgent_not_important),
      not_urgent_not_important: sortTasks(grouped.not_urgent_not_important),
    };
  }, [tasks, debouncedSearch, filterListId, filterPriority, selectedTags, horizonDays, todayYmd]);

  // --------------- derived data ---------------

  const isFilterActive = !!(search.trim() || filterListId || filterPriority !== null || selectedTags.size > 0);
  const totalActiveCount = tasks.filter((task) =>
    task.status === TASK_STATUS.open,
  ).length;

  const { copy, copying } = useCopyToClipboard();
  const handleCopyMatrix = useCallback(async () => {
    if (copying) return;
    const formatQuadrant = (title: string, items: Task[]): string[] => {
      const lines = [`${title} (${items.length}):`];
      if (items.length === 0) {
        lines.push(`  ${t('common.none')}`);
      } else {
        for (const task of items) {
          const pri = task.priority ? ` P${task.priority}` : '';
          const dur = task.estimated_minutes ? ` (${task.estimated_minutes}${t('common.min')})` : '';
          lines.push(`  - ${task.title}${pri}${dur}`);
        }
      }
      return lines;
    };

    const lines = [
      `${t('eisenhower.title')}\n`,
      ...formatQuadrant(t('eisenhower.urgentImportant'), quadrants.urgent_important),
      '',
      ...formatQuadrant(t('eisenhower.notUrgentImportant'), quadrants.not_urgent_important),
      '',
      ...formatQuadrant(t('eisenhower.urgentNotImportant'), quadrants.urgent_not_important),
      '',
      ...formatQuadrant(t('eisenhower.notUrgentNotImportant'), quadrants.not_urgent_not_important),
    ];
    await copy(lines.join('\n').trimEnd(), t('eisenhower.matrixCopied'));
  }, [copy, copying, quadrants, t]);

  // Flatten all quadrant tasks into a single ordered list for keyboard navigation
  const allFlatTasks = useMemo(() => [
    ...quadrants.urgent_important,
    ...quadrants.not_urgent_important,
    ...quadrants.urgent_not_important,
    ...quadrants.not_urgent_not_important,
  ], [quadrants]);

  const allFlatIds = useMemo(() => allFlatTasks.map((tk) => tk.id), [allFlatTasks]);

  const totalDurationMinutes = useMemo(
    () => allFlatTasks.reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0),
    [allFlatTasks],
  );

  // --------------- keyboard navigation ---------------

  const actions = useTaskListActions(allFlatTasks);

  const onMoveInView = useCallback((
    taskId: string,
    direction: -1 | 1,
    axis: 'horizontal' | 'vertical' = 'horizontal',
  ) => {
    const task = tasks.find((item) => item.id === taskId);
    if (!task) return false;
    if (axis === 'horizontal') {
      // Importance axis: ←  = make important, → = make non-important.
      const isCurrentlyImportant = task.priority != null && task.priority <= 2;
      const isTargetImportant = direction === -1;
      if (isCurrentlyImportant === isTargetImportant) return true;
      const isTaskUrgent = task.due_date != null
        && daysBetween(todayYmd, task.due_date) <= URGENT_DAYS_THRESHOLD;
      const targetQuadrant: QuadrantKey = isTargetImportant
        ? (isTaskUrgent ? 'urgent_important' : 'not_urgent_important')
        : (isTaskUrgent ? 'urgent_not_important' : 'not_urgent_not_important');
      handleDrop(targetQuadrant, taskId);
      return true;
    }
    // Urgency axis: ↑ = make urgent (due today, unless already
    // sooner), ↓ = make non-urgent (clear due_date). Quadrants are
    // derived from `URGENT_DAYS_THRESHOLD`-day window, so flipping the
    // due_date is enough to flip the row across the urgency divide.
    const isTaskUrgent = task.due_date != null
      && daysBetween(todayYmd, task.due_date) <= URGENT_DAYS_THRESHOLD;
    const wantUrgent = direction === -1;
    if (isTaskUrgent === wantUrgent) return true;
    if (wantUrgent) {
      // If the task already has a due date sooner than today (rare —
      // overdue), keep it; otherwise pull it forward to today so it
      // lands in the urgent half without overwriting an explicit
      // earlier deadline.
      const shouldKeepExistingDate = task.due_date != null
        && daysBetween(todayYmd, task.due_date) < 0;
      const nextDue = shouldKeepExistingDate ? task.due_date! : todayYmd;
      handleChangeDueDate(task, nextDue);
    } else {
      handleChangeDueDate(task, null);
    }
    return true;
  }, [tasks, handleDrop, handleChangeDueDate, todayYmd]);

  const keyboard = useTaskListKeyboard({
    taskIds: allFlatIds,
    onSelect: onSelectTask,
    actions: { ...actions, onMoveInView },
    disabled: isLoading || (isError && tasks.length === 0),
  });

  return {
    // i18n
    t,
    // query state
    isLoading,
    isError,
    refetch,
    // lists
    lists,
    // filter state
    search,
    setSearch,
    filterListId,
    setFilterListId,
    selectedTags,
    toggleTag,
    clearTagFilter,
    replaceSelectedTags,
    allTags,
    horizonDays,
    setHorizonDays,
    filterPriority,
    setFilterPriority,
    // drag state
    dragOverQuadrant,
    setDragOverQuadrant,
    // quadrant data
    quadrants,
    // derived
    isFilterActive,
    totalActiveCount,
    allFlatTasks,
    totalDurationMinutes,
    // copy
    copying,
    handleCopyMatrix,
    // mutation state — busy if either axis mutation is in flight
    changePriorityPending: isChangingPriority || isChangingDueDate,
    // drag-and-drop
    handleDrop,
    // keyboard
    keyboard,
    // actions (for overlays)
    actions,
  } as const;
}
