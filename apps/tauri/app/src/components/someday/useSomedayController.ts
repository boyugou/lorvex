import { useCallback, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import { quickCapture } from '@/lib/ipc/tasks/mutations/quickCapture';
import { getSomedayTasks } from '@/lib/ipc/tasks/queries';
import { reportClientError } from '@/lib/errors/errorLogging';
import { toast } from '@/lib/notifications/toast';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { QUERY_KEYS, invalidateTaskMutationQueries } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { useBulkActions } from '@/lib/tasks/useBulkActions';
import type { PriorityFilterValue } from '@/lib/tasks/priorityFilter';
import { useDebounced } from '@/lib/useDebounced';
import { useMounted } from '@/lib/useMounted';
import { useScrollRestore } from '@/lib/useScrollRestore';
import { useTaskListActions } from '@/lib/tasks/useTaskListActions';
import { useTaskListKeyboard } from '@/lib/tasks/useTaskListKeyboard';
import { useTaskSelection } from '@/lib/tasks/useTaskSelection';
import { useCollapsibleSections } from '@/lib/useCollapsibleSections';
import { useI18n } from '@/lib/i18n';
import { applyTaskFilters, useTaskFilters } from '@/lib/tasks/useTaskFilters';
import {
  buildListSections, buildPrioritySections, buildTagSections,
  sortSomedayTasks, SORT_KEYS, GROUP_BY_KEYS,
  type SomedaySortKey, type GroupBy, type SomedaySection,
} from './grouping';
import type { ListWithCount, Task } from '@/lib/ipc/tasks/models';

const COLLAPSE_PK = 'someday.collapsed';

interface SomedayControllerState {
  // i18n
  t: ReturnType<typeof useI18n>['t'];

  // scroll restore
  scroll: ReturnType<typeof useScrollRestore>;

  // data
  tasks: Task[];
  lists: ListWithCount[];
  isLoading: boolean;
  isError: boolean;
  refetch: () => void;

  // search + filter + sort
  search: string;
  setSearch: React.Dispatch<React.SetStateAction<string>>;
  sortKey: SomedaySortKey;
  setSortKey: React.Dispatch<React.SetStateAction<SomedaySortKey>>;
  groupBy: GroupBy;
  setGroupBy: React.Dispatch<React.SetStateAction<GroupBy>>;
  filterPriority: PriorityFilterValue;
  setFilterPriority: React.Dispatch<React.SetStateAction<PriorityFilterValue>>;
  filterListId: string | null;
  setFilterListId: (id: string | null) => void;
  selectedTags: Set<string>;
  toggleTag: (tag: string) => void;
  clearTagFilter: () => void;
  replaceSelectedTags: (tags: Iterable<string>) => void;
  allTags: string[];

  // derived
  filtered: Task[];
  sections: SomedaySection[];
  allFlatTasks: Task[];
  filteredIds: string[];

  // collapsed sections
  collapsedSections: Set<string>;
  toggleSection: (sectionKey: string) => void;

  // selection + bulk
  selectionMode: boolean;
  selectedIds: Set<string>;
  selectAll: () => void;
  toggleTaskSelected: (taskId: string) => void;
  setSelectionModeEnabled: (enabled: boolean) => void;
  setSelectedIds: React.Dispatch<React.SetStateAction<Set<string>>>;
  clearSelection: () => void;
  onClickWithModifiers: (id: string, event: ReactMouseEvent<HTMLButtonElement>) => void;
  bulk: ReturnType<typeof useBulkActions>;

  // task list actions + keyboard
  actions: ReturnType<typeof useTaskListActions>;
  keyboard: ReturnType<typeof useTaskListKeyboard>;

  // inline add
  addInputRef: React.RefObject<HTMLInputElement | null>;
  adding: boolean;
  handleAddSomeday: () => Promise<void>;

  // label maps
  sortLabels: Record<SomedaySortKey, string>;
  groupByLabels: Record<GroupBy, string>;

  // constants re-exported for the view
  sortKeys: readonly SomedaySortKey[];
  groupByKeys: readonly GroupBy[];
}

interface UseSomedayControllerArgs {
  onSelectTask?: ((taskId: string) => void) | undefined;
}

export function useSomedayController({ onSelectTask }: UseSomedayControllerArgs): SomedayControllerState {
  const { t, format } = useI18n();
  const qc = useQueryClient();
  const dayContext = useConfiguredDayContext();
  const scroll = useScrollRestore('someday');
  const mountedRef = useMounted();
  const [search, setSearch] = useState('');
  const [sortKey, setSortKey] = useState<SomedaySortKey>('newest');
  const [groupBy, setGroupBy] = useState<GroupBy>('none');
  const [filterPriority, setFilterPriority] = useState<PriorityFilterValue>(null);
  const { collapsed: collapsedSections, toggle: toggleSection } = useCollapsibleSections(COLLAPSE_PK);
  const addInputRef = useRef<HTMLInputElement>(null);
  const [adding, setAdding] = useState(false);

  const handleAddSomeday = async () => {
    const title = addInputRef.current?.value.trim();
    if (!title || adding) return;
    setAdding(true);
    try {
      await quickCapture({ title, status: 'someday' });
      invalidateTaskMutationQueries(qc);
      if (addInputRef.current) addInputRef.current.value = '';
    } catch (error) {
      reportClientError('someday.inlineAdd', 'Failed to add someday task', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (mountedRef.current) setAdding(false);
    }
  };

  const { data: tasks = [], isLoading, isError, refetch } = useQuery({
    queryKey: QUERY_KEYS.somedayTasks(),
    queryFn: ({ signal }) => getSomedayTasks(signal),
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
  } = useTaskFilters(tasks);

  // Debounce the search box so filter recomputation + section
  // grouping don't fire on every keystroke. Mirrors AllTasks /
  // Upcoming / Kanban. 300 ms matches the AllTasks tuning.
  const debouncedSearch = useDebounced(search, 300);
  const filtered = useMemo(() => {
    const result = applyTaskFilters(tasks, {
      listId: filterListId,
      priority: filterPriority,
      tags: selectedTags,
      search: debouncedSearch,
    });
    return sortSomedayTasks(result, sortKey);
  }, [tasks, debouncedSearch, sortKey, filterListId, filterPriority, selectedTags]);

  const sections = useMemo<SomedaySection[]>(() => {
    if (groupBy === 'none') {
      return [{ key: 'all', title: '', tasks: filtered }];
    }
    if (groupBy === 'list') {
      return buildListSections(filtered, lists, sortKey);
    }
    if (groupBy === 'priority') {
      return buildPrioritySections(filtered, sortKey, t);
    }
    // groupBy === 'tag'
    return buildTagSections(filtered, sortKey, t);
  }, [filtered, groupBy, lists, sortKey, t]);

  // Flatten sections (respecting collapsed state) for keyboard navigation
  const allFlatTasks = useMemo(() => {
    if (groupBy === 'none') return filtered;
    return sections.flatMap((s) =>
      collapsedSections.has(s.key) ? [] : s.tasks,
    );
  }, [sections, filtered, groupBy, collapsedSections]);

  const filteredIds = useMemo(() => allFlatTasks.map((tk) => tk.id), [allFlatTasks]);
  const filteredIdSet = useMemo(() => new Set(filteredIds), [filteredIds]);

  // Selection + bulk actions
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
  } = useTaskSelection(filteredIdSet, null, {
    // warn when a plain click silently collapses a
    // multi-selection so the user can recover the prior set.
    onSelectionCollapsedMessage: (count) =>
      format('allTasks.selectionCollapsed', { count: String(count) }),
    onSelectionCollapsedUndoLabel: () => t('allTasks.selectionCollapsedRestore'),
  });
  const bulk = useBulkActions({
    tasks: allFlatTasks,
    selectedIds,
    setSelectedIds,
    deferDateYmd: dayContext.tomorrowYmd,
  });

  const onExtendSelection = useCallback(
    (direction: 'up' | 'down', focusedId: string | null) =>
      handleKeyboardExtend(direction, filteredIds, focusedId),
    [handleKeyboardExtend, filteredIds],
  );
  const onClickWithModifiers = useCallback(
    (id: string, event: ReactMouseEvent<HTMLButtonElement>) =>
      handleClickWithModifiers(id, event, filteredIds, null),
    [handleClickWithModifiers, filteredIds],
  );

  const baseActions = useTaskListActions(allFlatTasks);
  const keyboardActions = {
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
    taskIds: filteredIds,
    onSelect: onSelectTask,
    actions: keyboardActions,
    disabled: isLoading,
  });

  const sortLabels: Record<SomedaySortKey, string> = {
    newest: t('someday.sortNewest'),
    oldest: t('someday.sortOldest'),
    priority: t('allTasks.sortPriority'),
    actionDate: t('allTasks.sortActionDate'),
  };

  const groupByLabels: Record<GroupBy, string> = {
    none: t('someday.groupByNone'),
    list: t('someday.groupByList'),
    priority: t('someday.groupByPriority'),
    tag: t('allTasks.groupByTag'),
  };

  return {
    t,
    scroll,
    tasks,
    lists,
    isLoading,
    isError,
    refetch: () => { void refetch(); },
    search,
    setSearch,
    sortKey,
    setSortKey,
    groupBy,
    setGroupBy,
    filterPriority,
    setFilterPriority,
    filterListId,
    setFilterListId,
    selectedTags,
    toggleTag,
    clearTagFilter,
    replaceSelectedTags,
    allTags,
    filtered,
    sections,
    allFlatTasks,
    filteredIds,
    collapsedSections,
    toggleSection,
    selectionMode,
    selectedIds,
    selectAll,
    toggleTaskSelected,
    setSelectionModeEnabled,
    setSelectedIds,
    clearSelection,
    onClickWithModifiers,
    bulk,
    actions: baseActions,
    keyboard,
    addInputRef,
    adding,
    handleAddSomeday,
    sortLabels,
    groupByLabels,
    sortKeys: SORT_KEYS,
    groupByKeys: GROUP_BY_KEYS,
  };
}
