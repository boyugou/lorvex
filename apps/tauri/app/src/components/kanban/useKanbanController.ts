import { useCallback, useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import type { Task } from '@/lib/ipc/tasks/models';
import { getAllTasks } from '@/lib/ipc/tasks/queries';
import { announce } from '@/lib/announce';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { daysBetween } from '@/lib/timeUtils';
import { useI18n } from '@/lib/i18n';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import { useDebounced } from '@/lib/useDebounced';
import { applyTaskFilters, useTaskFilters } from '@/lib/tasks/useTaskFilters';
import { useTaskListActions } from '@/lib/tasks/useTaskListActions';
import { useTaskListKeyboard } from '@/lib/tasks/useTaskListKeyboard';
import { compareTaskByPriorityThenDue } from '@/lib/tasks/taskComparators';
import {
  COLUMN_LABEL_KEYS, COLUMN_ORDER, STATUS_TO_COLUMN,
  type ColumnKey,
} from './columns';
import { isKanbanMoveAxisHandled, type TaskMoveAxis } from './moveAxis.logic';
import type { HorizonValue } from '../ui/TimeHorizonPicker';
import { useKanbanColumnActions } from './useKanbanColumnActions';
import {
  isString,
  useLocalStorageBackedState,
} from '@/lib/storage/useLocalStorageBackedState';
import {
  isPriorityOrNull,
  type PriorityFilterValue,
} from '@/lib/tasks/priorityFilter';
import { getUIStateBoolean, setUIStateBoolean } from '@/lib/storage/uiState';

const PK = 'kanban.';
const TASK_FILTER_PERSISTENCE = {
  filterListIdKey: PK + 'filterListId',
  selectedTagsKey: PK + 'selectedTags',
} as const;

function isHorizonValue(value: unknown): value is HorizonValue {
  return value === null || typeof value === 'number';
}

interface UseKanbanControllerOptions {
  onSelectTask?: ((taskId: string) => void) | undefined;
}

export function useKanbanController({ onSelectTask }: UseKanbanControllerOptions) {
  const { t } = useI18n();
  const { todayYmd } = useConfiguredDayContext();
  // persist view-state per-view so a refresh keeps
  // showCompleted, search, time-horizon, and filter pills intact.
  const [showCompleted, setShowCompletedRaw] = useState(() =>
    getUIStateBoolean(PK + 'showCompleted', false),
  );
  const setShowCompleted = useCallback((next: boolean | ((prev: boolean) => boolean)) => {
    setShowCompletedRaw((prev) => {
      const value = typeof next === 'function' ? next(prev) : next;
      setUIStateBoolean(PK + 'showCompleted', value);
      return value;
    });
  }, []);
  const [search, setSearch] = useLocalStorageBackedState<string>(PK + 'search', '', isString);
  const [dragOverColumn, setDragOverColumn] = useState<ColumnKey | null>(null);
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
    queryKey: QUERY_KEYS.allTasks(showCompleted, false),
    queryFn: ({ signal }) => getAllTasks(showCompleted, false, signal),
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

  const { handleMoveToColumn, isMovingToColumn } = useKanbanColumnActions({ t });

  const handleDrop = useCallback(
    (targetColumn: ColumnKey, taskId: string) => {
      setDragOverColumn(null);
      const task = tasks.find((item) => item.id === taskId);
      if (!task) return;
      const sourceColumn = STATUS_TO_COLUMN[task.status];
      if (sourceColumn === targetColumn) return;
      handleMoveToColumn(taskId, targetColumn);
    },
    [handleMoveToColumn, tasks],
  );

  // --------------- filtering & columns ---------------

  // Debounce the search box so filter recomputation + virtualizer
  // re-measure don't fire on every keystroke. Mirrors AllTasks /
  // Upcoming. 300 ms matches the AllTasks tuning.
  const debouncedSearch = useDebounced(search, 300);
  const filteredTasks = useMemo(() => {
    // Pre-filter by list, then delegate standard tag + search filtering to
    // the shared utility. Legacy no-list tasks are a repair state, not a
    // first-class board filter.
    let result = tasks;
    if (filterListId) {
      result = result.filter((task) => task.list_id === filterListId);
    }
    result = applyTaskFilters(result, {
      tags: selectedTags,
      search: debouncedSearch,
      priority: filterPriority,
    });
    // Exclude tasks beyond the selected time horizon
    if (horizonDays !== null) {
      result = result.filter((task) => {
        if (!task.due_date) return true;
        return daysBetween(todayYmd, task.due_date) <= horizonDays;
      });
    }
    return result;
  }, [tasks, filterListId, selectedTags, debouncedSearch, filterPriority, horizonDays, todayYmd]);

  const columns = useMemo(() => {
    const grouped: Record<ColumnKey, Task[]> = {
      open: [],
      someday: [],
      completed: [],
    };

    for (const task of filteredTasks) {
      const column = STATUS_TO_COLUMN[task.status];
      if (column) grouped[column].push(task);
    }

    const sortByImportance = (items: Task[]) => items.sort(compareTaskByPriorityThenDue);

    return {
      open: sortByImportance(grouped.open),
      someday: sortByImportance(grouped.someday),
      completed: grouped.completed.sort((a, b) =>
        (b.completed_at ?? b.updated_at).localeCompare(a.completed_at ?? a.updated_at),
      ),
    };
  }, [filteredTasks]);

  // --------------- derived data ---------------

  const isFilterActive = !!(search.trim() || filterListId || filterPriority !== null || selectedTags.size > 0);
  const totalTaskCount = tasks.length;

  const { copy, copying } = useCopyToClipboard();
  const handleCopyBoard = useCallback(async () => {
    if (copying) return;
    const lines: string[] = [`${t('kanban.title')}\n`];
    for (const key of COLUMN_ORDER) {
      if (key === 'completed' && !showCompleted) continue;
      const colTasks = columns[key];
      lines.push(`${t(COLUMN_LABEL_KEYS[key])} (${colTasks.length}):`);
      if (colTasks.length === 0) {
        lines.push(`  ${t('common.none')}`);
      } else {
        for (const task of colTasks) {
          const pri = task.priority ? ` P${task.priority}` : '';
          const dur = task.estimated_minutes ? ` (${task.estimated_minutes}${t('common.min')})` : '';
          lines.push(`  - ${task.title}${pri}${dur}`);
        }
      }
      lines.push('');
    }
    await copy(lines.join('\n').trimEnd(), t('kanban.boardCopied'));
  }, [columns, copy, copying, showCompleted, t]);

  // Flatten visible column tasks into a single ordered list for keyboard navigation
  const visibleColumnKeys = showCompleted ? COLUMN_ORDER : COLUMN_ORDER.filter((k) => k !== 'completed');
  const allFlatTasks = useMemo(() =>
    visibleColumnKeys.flatMap((key) => columns[key]),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- visibleColumnKeys derived from showCompleted
    [columns, showCompleted],
  );
  const allFlatIds = useMemo(() => allFlatTasks.map((tk) => tk.id), [allFlatTasks]);

  // --------------- keyboard navigation ---------------

  const kbActions = useTaskListActions(allFlatTasks);

  const onMoveInView = useCallback((taskId: string, direction: -1 | 1, axis?: TaskMoveAxis) => {
    if (!isKanbanMoveAxisHandled(axis)) return false;
    const task = tasks.find((item) => item.id === taskId);
    if (!task) return false;
    const currentColumn = STATUS_TO_COLUMN[task.status];
    if (!currentColumn) return true;
    const currentIdx = visibleColumnKeys.indexOf(currentColumn);
    if (currentIdx < 0) return true;
    const targetIdx = currentIdx + direction;
    if (targetIdx < 0 || targetIdx >= visibleColumnKeys.length) return true;
    const targetColumn = visibleColumnKeys[targetIdx] as ColumnKey | undefined;
    if (!targetColumn) return true;
    handleDrop(targetColumn, taskId);
    // keyboard-driven Kanban move produces no toast —
    // announce the new column to SR users so they know the action
    // landed without Tab-ing back to inspect.
    announce(`${t('kanban.moved')}: ${t(COLUMN_LABEL_KEYS[targetColumn])}`);
    return true;
  }, [tasks, visibleColumnKeys, handleDrop, t]);

  const keyboard = useTaskListKeyboard({
    taskIds: allFlatIds,
    onSelect: onSelectTask,
    actions: { ...kbActions, onMoveInView },
    disabled: isLoading || (isError && tasks.length === 0),
  });

  const totalCount = filteredTasks.length;

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
    // column visibility
    showCompleted,
    setShowCompleted,
    // drag state
    dragOverColumn,
    setDragOverColumn,
    // column data
    filteredTasks,
    columns,
    visibleColumnKeys,
    // derived
    isFilterActive,
    totalTaskCount,
    totalCount,
    allFlatTasks,
    // copy
    copying,
    handleCopyBoard,
    // mutation state
    moveToColumnPending: isMovingToColumn,
    // drag-and-drop
    handleDrop,
    // keyboard
    keyboard,
    // actions (for overlays)
    kbActions,
  } as const;
}

export type KanbanController = ReturnType<typeof useKanbanController>;
