import { useCallback, useMemo, useState } from 'react';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_SHORT, STALE_DEFAULT } from '@/lib/query/timing';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import { getAllTasks } from '@/lib/ipc/tasks/queries';
import { parseTags } from '@/lib/format';
import type { Task } from '@/lib/ipc/tasks/models';
import { useBulkActions } from '@/lib/tasks/useBulkActions';
import {
  buildListGroupedTaskSections,
  partitionTasksByListOwnership,
} from '@/lib/tasks/listOwnership';
import { applyTaskFilters, useTaskFilters } from '@/lib/tasks/useTaskFilters';
import { useTaskSortState } from '@/lib/tasks/useTaskSortState';
import { classifyTaskRelativeSection } from '@/lib/tasks/dayBuckets';
import { useI18n } from '@/lib/i18n';
import {
  getUIStateBoolean,
  getUIStateString,
  setUIState,
  setUIStateBoolean,
} from '@/lib/storage/uiState';
import {
  isString,
  useLocalStorageBackedState,
} from '@/lib/storage/useLocalStorageBackedState';
import {
  isPriorityOrNull,
  type PriorityFilterValue,
} from '@/lib/tasks/priorityFilter';
import { useCollapsibleSections } from '@/lib/useCollapsibleSections';
import { useDebounced } from '@/lib/useDebounced';
import { useAllTasksSelection } from './controller/selection';
import {
  resolveCompletedSectionSortDirection,
  sortTasks,
} from '@/lib/tasks/taskSorting';
import type { SortDirection, SortKey } from '@/lib/tasks/taskSorting';
import type { BulkAction, GroupBy, TaskSection } from './types';
import { GROUP_BY_KEYS } from './types';
import { TASK_STATUS } from '@lorvex/shared/types';

/** Canonical prefixed-key stem (stored as `lorvex:allTasks.*`). */
const PK = 'allTasks.';
const COLLAPSE_PK = PK + 'collapsed';
const TASK_FILTER_PERSISTENCE = {
  filterListIdKey: PK + 'filterListId',
  selectedTagsKey: PK + 'selectedTags',
} as const;

function readBool(key: string, fallback: boolean): boolean {
  return getUIStateBoolean(PK + key, fallback);
}

function readGroupBy(): GroupBy {
  const v = getUIStateString(PK + 'groupBy', '');
  if (v && (GROUP_BY_KEYS as readonly string[]).includes(v)) return v as GroupBy;
  return 'status';
}

function writeStringPref(key: string, value: string): void {
  setUIState(PK + key, value);
}

function writeBooleanPref(key: string, value: boolean): void {
  setUIStateBoolean(PK + key, value);
}

export interface AllTasksViewProps {
  onSelectTask?: ((taskId: string) => void) | undefined;
  /** Pre-fill the search field (e.g. from a search deep link). */
  initialSearch?: string | undefined;
  /**
   * Opens the QuickCapture overlay. Wired to the header "+ Add task"
   * button so every entity-list view offers a consistent, top-right
   * add-entry point in addition to the global ⌘N shortcut.
   */
  onAddTask?: (() => void) | undefined;
}

export function buildStatusSections(
  authoredTasks: Task[],
  sortKey: SortKey,
  sortDirection: SortDirection,
  labels: Record<'open' | 'someday' | 'cancelled' | 'completed', string>,
): TaskSection[] {
  const completedSectionSortKey = sortKey === 'default' ? 'completedAt' : sortKey;
  const completedSectionSortDirection = resolveCompletedSectionSortDirection(sortKey, sortDirection);
  const sections: TaskSection[] = [
    { key: 'open', title: labels.open, tasks: sortTasks(authoredTasks.filter((task) => task.status === TASK_STATUS.open), sortKey, sortDirection) },
    { key: 'someday', title: labels.someday, tasks: sortTasks(authoredTasks.filter((task) => task.status === TASK_STATUS.someday), sortKey, sortDirection) },
    { key: 'cancelled', title: labels.cancelled, tasks: sortTasks(authoredTasks.filter((task) => task.status === TASK_STATUS.cancelled), completedSectionSortKey, completedSectionSortDirection), completed: true },
    { key: 'completed', title: labels.completed, tasks: sortTasks(authoredTasks.filter((task) => task.status === TASK_STATUS.completed), completedSectionSortKey, completedSectionSortDirection), completed: true },
  ];
  return sections.filter((section) => section.tasks.length > 0);
}

export function useAllTasksController(initialSearch?: string) {
  const { t } = useI18n();
  const dayContext = useConfiguredDayContext();
  // persist search/filter state per-view so a refresh
  // doesn't drop the user's filter pills + search query. The deep-link
  // `initialSearch` always wins (an explicit user intent), otherwise
  // we restore the persisted value.
  const [searchPersisted, setSearchPersisted] = useLocalStorageBackedState<string>(
    PK + 'search',
    '',
    isString,
  );
  // `initialSearch === ''` is a real deep-link intent ("clear the
  // search"), distinct from "no deep link". A strict `=== undefined`
  // check ensures an explicit empty string wins and erases the
  // persisted query; `??` would collapse empty strings into the
  // persisted value.
  const [search, setSearchInternal] = useState(
    initialSearch !== undefined ? initialSearch : searchPersisted,
  );
  const setSearch = useCallback(
    (next: React.SetStateAction<string>) => {
      setSearchInternal((prev) => {
        const value = typeof next === 'function' ? (next as (p: string) => string)(prev) : next;
        setSearchPersisted(value);
        return value;
      });
    },
    [setSearchPersisted],
  );
  const [filterPriority, setFilterPriority] = useLocalStorageBackedState<PriorityFilterValue>(
    PK + 'filterPriority',
    null,
    isPriorityOrNull,
  );
  const [showCompleted, setShowCompletedRaw] = useState(() => readBool('showCompleted', false));
  const [showCancelled, setShowCancelledRaw] = useState(() => readBool('showCancelled', false));

  const { sortKey, setSortKey, sortDirection, setSortDirection, toggleSortDirection } = useTaskSortState({
    storagePrefix: PK,
  });

  const setShowCompleted = useCallback((v: boolean | ((prev: boolean) => boolean)) => {
    setShowCompletedRaw((prev) => {
      const next = typeof v === 'function' ? v(prev) : v;
      writeBooleanPref('showCompleted', next);
      return next;
    });
  }, []);

  const setShowCancelled = useCallback((v: boolean | ((prev: boolean) => boolean)) => {
    setShowCancelledRaw((prev) => {
      const next = typeof v === 'function' ? v(prev) : v;
      writeBooleanPref('showCancelled', next);
      return next;
    });
  }, []);

  const [groupBy, setGroupByRaw] = useState<GroupBy>(readGroupBy);
  const setGroupBy = useCallback((v: GroupBy) => {
    setGroupByRaw(v);
    writeStringPref('groupBy', v);
  }, []);
  const [bulkAction, setBulkAction] = useState<BulkAction>(null);

  const {
    collapsed: collapsedSections,
    toggle: toggleSectionCollapse,
    collapseAll: collapseAllSections,
    expandAll: expandAllSections,
  } = useCollapsibleSections(COLLAPSE_PK);

  const debouncedSearch = useDebounced(search, 300);

  const {
    data: allTasks = [],
    isLoading,
    isError: isAllTasksError,
    refetch: refetchAllTasks,
  } = useQuery({
    queryKey: QUERY_KEYS.allTasks(showCompleted, showCancelled),
    queryFn: ({ signal }) => getAllTasks(showCompleted, showCancelled, signal),
    staleTime: STALE_SHORT,
    placeholderData: keepPreviousData,
  });

  const { data: listsData } = useQuery({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
  });
  const lists = listsData ?? [];

  const {
    filterListId,
    setFilterListId,
    selectedTags,
    toggleTag,
    clearTagFilter,
    replaceSelectedTags,
    allTags,
  } = useTaskFilters(allTasks, TASK_FILTER_PERSISTENCE);

  const tasks = useMemo(
    () => applyTaskFilters(allTasks, {
      listId: filterListId,
      priority: filterPriority,
      tags: selectedTags,
      search: debouncedSearch,
      searchTags: true,
    }),
    [allTasks, debouncedSearch, filterListId, filterPriority, selectedTags],
  );
  const { authoredTasks } = useMemo(
    () => partitionTasksByListOwnership(tasks, listsData),
    [listsData, tasks],
  );

  const hasActiveFilter = useMemo(
    () => !!(debouncedSearch.trim() || filterListId || filterPriority !== null || selectedTags.size > 0),
    [debouncedSearch, filterListId, filterPriority, selectedTags],
  );

  const emptyTitleLabel = useMemo(() => {
    if (!hasActiveFilter || allTasks.length === 0) return t('allTasks.emptyNoTasks');
    const q = debouncedSearch.trim();
    return q.length >= 2
      ? `${t('allTasks.emptyNoMatch')} "${q}"`
      : t('allTasks.emptyNoMatch');
  }, [allTasks.length, debouncedSearch, hasActiveFilter, t]);

  const emptyHintLabel = useMemo(() => {
    if (!hasActiveFilter || allTasks.length === 0) return t('allTasks.emptyHint');
    return t('allTasks.emptySearchHint');
  }, [allTasks.length, hasActiveFilter, t]);

  const visibleTaskIds = useMemo(() => new Set(authoredTasks.map((task) => task.id)), [authoredTasks]);

  const selection = useAllTasksSelection(visibleTaskIds, bulkAction);

  const statusSections = useMemo<TaskSection[]>(() => {
    return buildStatusSections(authoredTasks, sortKey, sortDirection, {
      open: t('allTasks.open'),
      someday: t('allTasks.someday'),
      cancelled: t('allTasks.cancelled'),
      completed: t('allTasks.completed'),
    });
  }, [authoredTasks, sortDirection, sortKey, t]);

  const listSections = useMemo<TaskSection[]>(() => {
    return buildListGroupedTaskSections(authoredTasks, listsData, {
      loadingLabel: t('common.loading'),
      sortTasks: (sectionTasks) => sortTasks(sectionTasks, sortKey, sortDirection),
    });
  }, [authoredTasks, listsData, sortDirection, sortKey, t]);

  const dueDateSections = useMemo<TaskSection[]>(() => {
    const bOverdue: typeof authoredTasks = [];
    const bToday: typeof authoredTasks = [];
    const bTomorrow: typeof authoredTasks = [];
    const bThisWeek: typeof authoredTasks = [];
    const bLater: typeof authoredTasks = [];
    const bNoDate: typeof authoredTasks = [];
    for (const task of authoredTasks) {
      switch (classifyTaskRelativeSection(task, dayContext.todayYmd)) {
        case 'overdue':
          bOverdue.push(task);
          break;
        case 'today':
          bToday.push(task);
          break;
        case 'tomorrow':
          bTomorrow.push(task);
          break;
        case 'this_week':
          bThisWeek.push(task);
          break;
        case 'later':
          bLater.push(task);
          break;
        case 'no_date':
          bNoDate.push(task);
          break;
      }
    }

    const sectionDefs: Array<{ key: string; titleKey: string; tasks: typeof authoredTasks }> = [
      { key: 'overdue', titleKey: 'allTasks.groupOverdue', tasks: bOverdue },
      { key: 'today', titleKey: 'allTasks.groupToday', tasks: bToday },
      { key: 'tomorrow', titleKey: 'allTasks.groupTomorrow', tasks: bTomorrow },
      { key: 'this_week', titleKey: 'allTasks.groupThisWeek', tasks: bThisWeek },
      { key: 'later', titleKey: 'allTasks.groupLater', tasks: bLater },
      { key: 'no_date', titleKey: 'allTasks.groupNoDate', tasks: bNoDate },
    ];

    const sections = sectionDefs
      .filter((s) => s.tasks.length > 0)
      .map((s) => ({
        key: `due-${s.key}`,
        title: t(s.titleKey as Parameters<typeof t>[0]),
        tasks: sortTasks(s.tasks, sortKey, sortDirection),
      }));
    return sections;
  }, [authoredTasks, dayContext.todayYmd, sortDirection, sortKey, t]);

  const prioritySections = useMemo<TaskSection[]>(() => {
    const p1: typeof authoredTasks = [];
    const p2: typeof authoredTasks = [];
    const p3: typeof authoredTasks = [];
    const noPriority: typeof authoredTasks = [];
    for (const task of authoredTasks) {
      const p = task.priority;
      if (p === 1) p1.push(task);
      else if (p === 2) p2.push(task);
      else if (p === 3) p3.push(task);
      else noPriority.push(task);
    }
    const sectionDefs: Array<{ key: string; titleKey: string; tasks: typeof authoredTasks }> = [
      { key: 'p1', titleKey: 'allTasks.groupP1', tasks: p1 },
      { key: 'p2', titleKey: 'allTasks.groupP2', tasks: p2 },
      { key: 'p3', titleKey: 'allTasks.groupP3', tasks: p3 },
      { key: 'none', titleKey: 'allTasks.groupNoPriority', tasks: noPriority },
    ];
    const sections = sectionDefs
      .filter((s) => s.tasks.length > 0)
      .map((s) => ({
        key: `priority-${s.key}`,
        title: t(s.titleKey as Parameters<typeof t>[0]),
        tasks: sortTasks(s.tasks, sortKey, sortDirection),
      }));
    return sections;
  }, [authoredTasks, sortDirection, sortKey, t]);

  const tagSections = useMemo<TaskSection[]>(() => {
    const tagBuckets = new Map<string, typeof authoredTasks>();
    const noTagTasks: typeof authoredTasks = [];
    for (const task of authoredTasks) {
      const taskTags = parseTags(task.tags);
      if (taskTags.length === 0) {
        noTagTasks.push(task);
      } else {
        for (const tag of taskTags) {
          const bucket = tagBuckets.get(tag);
          if (bucket) bucket.push(task);
          else tagBuckets.set(tag, [task]);
        }
      }
    }
    const sections: TaskSection[] = [];
    for (const [tag, tagTasks] of [...tagBuckets.entries()].sort(([a], [b]) => a.localeCompare(b))) {
      sections.push({ key: `tag-${tag}`, title: tag, tasks: sortTasks(tagTasks, sortKey, sortDirection) });
    }
    if (noTagTasks.length > 0) {
      sections.push({ key: 'tag-none', title: t('allTasks.groupNoTag'), tasks: sortTasks(noTagTasks, sortKey, sortDirection) });
    }
    return sections;
  }, [authoredTasks, sortDirection, sortKey, t]);

  const sectionMap: Record<GroupBy, TaskSection[]> = {
    status: statusSections,
    list: listSections,
    due_date: dueDateSections,
    priority: prioritySections,
    tag: tagSections,
  };
  const sections = sectionMap[groupBy];

  const bulk = useBulkActions({
    tasks: authoredTasks,
    selectedIds: selection.selectedIds,
    setSelectedIds: selection.setSelectedIds,
    deferDateYmd: dayContext.tomorrowYmd,
    targetListId: selection.targetListId,
    externalBulkAction: bulkAction,
    externalSetBulkAction: setBulkAction,
  });

  return {
    allTags,
    bulkAction: bulk.bulkAction,
    clearTagFilter,
    collapseAllSections,
    collapsedSections,
    emptyHintLabel,
    emptyTitleLabel,
    expandAllSections,
    filterListId,
    filterPriority,
    groupBy,
    handleBulkCancel: bulk.handleBulkCancel,
    handleBulkComplete: bulk.handleBulkComplete,
    handleBulkMove: bulk.handleBulkMove,
    handleBulkDefer: bulk.handleBulkDefer,
    isAllTasksError,
    isLoading,
    lists,
    refetchAllTasks,
    search,
    sections,
    selectAll: selection.selectAll,
    selectedCount: bulk.selectedCount,
    selectedIds: selection.selectedIds,
    selectedTags,
    selectionMode: selection.selectionMode,
    setFilterListId,
    setFilterPriority,
    setGroupBy,
    setSearch,
    setSelectedIds: selection.setSelectedIds,
    setSelectionModeEnabled: selection.setSelectionModeEnabled,
    setShowCancelled,
    setShowCompleted,
    setSortKey,
    setSortDirection,
    setTargetListId: selection.setTargetListId,
    showCancelled,
    showCompleted,
    sortDirection,
    sortKey,
    toggleSortDirection,
    targetListId: selection.targetListId,
    tasks,
    totalCount: allTasks.length,
    hasActiveFilter,
    toggleSectionCollapse,
    toggleTag,
    replaceSelectedTags,
    toggleTaskSelected: selection.toggleTaskSelected,
    clearSelection: selection.clearSelection,
    handleClickWithModifiers: selection.handleClickWithModifiers,
    handleKeyboardExtend: selection.handleKeyboardExtend,
  };
}
