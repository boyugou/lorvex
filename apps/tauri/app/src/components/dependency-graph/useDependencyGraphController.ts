import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import type { ListWithCount, Task } from '@/lib/ipc/tasks/models';
import { getAllTasks } from '@/lib/ipc/tasks/queries';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { applyTaskFilters, useTaskFilters } from '@/lib/tasks/useTaskFilters';
import { useTaskListActions, type TaskListActionsResult } from '@/lib/tasks/useTaskListActions';
import { useTaskListKeyboard, type TaskListKeyboardState } from '@/lib/tasks/useTaskListKeyboard';
import { useDebounced } from '@/lib/useDebounced';
import {
  buildClusters,
  isDependencyGraphActiveTask,
  isDependencyGraphTerminalTask,
  parseIdList,
  type FilteredCluster,
} from './clustering';
import { useClusterJumpNavigation } from './useClusterJumpNavigation';
import { TASK_STATUS } from '@lorvex/shared/types';

export type FilterMode = 'all' | 'blocked' | 'ready';

interface UseDependencyGraphControllerOptions {
  onSelectTask?: ((taskId: string) => void) | undefined;
  /**
   * Cluster ids currently collapsed by the parent view. Forwarded
   * into `useClusterJumpNavigation` so Shift+J/K can expand a
   * collapsed target cluster before placing focus inside it.
   */
  collapsedClusterIds: Set<string>;
  /** Toggle handler the jump nav calls to expand a collapsed target. */
  expandCluster: (clusterId: string) => void;
}

interface DependencyGraphController {
  // State
  filter: FilterMode;
  setFilter: (f: FilterMode) => void;
  search: string;
  setSearch: (s: string) => void;
  hideCompleted: boolean;
  setHideCompleted: (v: boolean | ((prev: boolean) => boolean)) => void;

  // Query state
  isLoading: boolean;
  isError: boolean;
  refetch: () => void;

  // Filter state
  filterListId: string | null;
  setFilterListId: (id: string | null) => void;
  selectedTags: Set<string>;
  toggleTag: (tag: string) => void;
  clearTagFilter: () => void;
  allTags: string[];

  // Data
  lists: ListWithCount[];
  clusters: ReturnType<typeof buildClusters>;
  filteredClusters: FilteredCluster[];
  taskMap: Map<string, Task>;
  allFlatTasks: Task[];

  // Derived stats
  isFilterActive: boolean;
  totalDepsExist: boolean;
  totalWithDeps: number;
  totalBlocked: number;
  totalReady: number;

  // Actions & keyboard
  actions: TaskListActionsResult;
  keyboard: TaskListKeyboardState;
}

export function useDependencyGraphController({
  onSelectTask,
  collapsedClusterIds,
  expandCluster,
}: UseDependencyGraphControllerOptions): DependencyGraphController {
  const [filter, setFilter] = useState<FilterMode>('all');
  const [search, setSearch] = useState('');
  const [hideCompleted, setHideCompleted] = useState(false);

  const { data: tasks = [], isLoading, isError, refetch } = useQuery({
    queryKey: QUERY_KEYS.allTasks(false, false),
    queryFn: ({ signal }) => getAllTasks(false, false, signal),
  });

  const { data: lists = [] } = useQuery({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
  });

  const { filterListId, setFilterListId, selectedTags, toggleTag, clearTagFilter, allTags } = useTaskFilters(tasks);

  const filteredByList = useMemo(() => {
    let result = tasks;
    if (hideCompleted) {
      result = result.filter((task) => task.status !== TASK_STATUS.completed);
    }
    return applyTaskFilters(result, { listId: filterListId, tags: selectedTags });
  }, [tasks, filterListId, selectedTags, hideCompleted]);

  const clusters = useMemo(() => buildClusters(filteredByList), [filteredByList]);

  // Build a lookup from task ID -> task for dependency title resolution.
  // Uses all tasks (not just filtered) so cross-cluster deps still resolve titles.
  const taskMap = useMemo(() => {
    const map = new Map<string, Task>();
    for (const task of tasks) map.set(task.id, task);
    return map;
  }, [tasks]);

  const isFilterActive = !!(search.trim() || filter !== 'all' || filterListId || selectedTags.size > 0 || hideCompleted);
  const totalDepsExist = useMemo(
    () => tasks.some((task) => task.depends_on && task.depends_on.length > 0),
    [tasks],
  );

  // Debounce the search box so the per-cluster filter pass + layout
  // recompute don't fire on every keystroke. The graph already does
  // O(N) work per cluster; without debouncing a fast typist with a
  // 500-task graph runs the full pipeline 5+ times in a single
  // word.
  const debouncedSearch = useDebounced(search, 300);

  // Compute filtered layers once per cluster; avoids duplicating filter logic in both
  // hasVisibleContent and ClusterSection.
  const filteredClusters = useMemo((): FilteredCluster[] => {
    const q = debouncedSearch.trim().toLowerCase();

    // Fast path: no search/mode filter -- all layers are visible as-is.
    if (filter === 'all' && !q) {
      return clusters.map((cluster) => ({ cluster, filteredLayers: cluster.layers }));
    }

    const result: FilteredCluster[] = [];
    for (const cluster of clusters) {
      const allClusterTasks = cluster.layers.flat();
      const terminalIds = new Set(
        allClusterTasks.filter(isDependencyGraphTerminalTask).map((t) => t.id),
      );
      const clusterIds = new Set(allClusterTasks.map((t) => t.id));

      const isBlocked = (task: Task): boolean => {
        if (!isDependencyGraphActiveTask(task)) return false;
        return parseIdList(task.depends_on).some(
          (dep) => clusterIds.has(dep) && !terminalIds.has(dep),
        );
      };

      const filteredLayers = cluster.layers
        .map((layer) => {
          let visible = layer;
          if (filter === 'blocked') visible = visible.filter((t) => isBlocked(t));
          else if (filter === 'ready') visible = visible.filter((t) => isDependencyGraphActiveTask(t) && !isBlocked(t));
          if (q) visible = visible.filter(
            (t) => t.title.toLowerCase().includes(q) || !!(t.body && t.body.toLowerCase().includes(q)),
          );
          return visible;
        })
        .filter((layer) => layer.length > 0);

      if (filteredLayers.length > 0) result.push({ cluster, filteredLayers });
    }
    return result;
  }, [clusters, filter, debouncedSearch]);

  // Flatten visible (filtered) cluster tasks for keyboard navigation
  const allFlatTasks = useMemo(() => filteredClusters.flatMap((fc) => fc.filteredLayers.flat()), [filteredClusters]);
  const allFlatIds = useMemo(() => allFlatTasks.map((tk) => tk.id), [allFlatTasks]);

  const actions = useTaskListActions(allFlatTasks);
  const keyboard = useTaskListKeyboard({
    taskIds: allFlatIds,
    onSelect: onSelectTask,
    actions,
    disabled: isLoading || isError,
  });

  // Shift+j/k jumps between clusters; plain j/k continues to
  // walk within the cluster via `useTaskListKeyboard`'s flat list.
  // Tab is left to the browser so native focus order across the
  // header chrome stays intact.
  useClusterJumpNavigation({
    filteredClusters,
    focusedTaskId: keyboard.focusedId,
    setFocusedTaskId: keyboard.focusTaskId,
    collapsedClusterIds,
    expandCluster,
    disabled: isLoading || isError,
  });

  // Page-level totals mirror the per-cluster header chips: derived from
  // `filteredClusters` so they shrink in lockstep with search/mode/list
  // filters. The user's mental model is "what am I looking at right
  // now," so a global summary computed off the pre-filter `clusters`
  // pool would contradict every visible per-cluster chip.
  const { totalWithDeps, totalBlocked, totalReady } = useMemo(() => {
    let withDeps = 0;
    let blocked = 0;
    let ready = 0;
    for (const { cluster, filteredLayers } of filteredClusters) {
      const allClusterTasks = cluster.layers.flat();
      const terminalIds = new Set(
        allClusterTasks.filter(isDependencyGraphTerminalTask).map((t) => t.id),
      );
      const clusterIds = new Set(allClusterTasks.map((t) => t.id));
      const isBlocked = (task: Task): boolean => {
        if (!isDependencyGraphActiveTask(task)) return false;
        return parseIdList(task.depends_on).some(
          (dep) => clusterIds.has(dep) && !terminalIds.has(dep),
        );
      };
      for (const task of filteredLayers.flat()) {
        withDeps += 1;
        if (isDependencyGraphTerminalTask(task)) continue;
        if (isBlocked(task)) blocked += 1;
        else if (isDependencyGraphActiveTask(task)) ready += 1;
      }
    }
    return { totalWithDeps: withDeps, totalBlocked: blocked, totalReady: ready };
  }, [filteredClusters]);

  return {
    filter,
    setFilter,
    search,
    setSearch,
    hideCompleted,
    setHideCompleted,
    isLoading,
    isError,
    refetch: () => { void refetch(); },
    filterListId,
    setFilterListId,
    selectedTags,
    toggleTag,
    clearTagFilter,
    allTags,
    lists,
    clusters,
    filteredClusters,
    taskMap,
    allFlatTasks,
    isFilterActive,
    totalDepsExist,
    totalWithDeps,
    totalBlocked,
    totalReady,
    actions,
    keyboard,
  };
}
