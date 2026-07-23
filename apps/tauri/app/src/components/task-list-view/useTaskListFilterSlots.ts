import { useMemo } from 'react';
import type { ListWithCount } from '@/lib/ipc/tasks/models';
import type { PriorityFilterValue } from '@/lib/tasks/priorityFilter';

/**
 * Shared `useMemo` builder for the four filter slots every task-list
 * view feeds into `<ViewToolbar>`. The four views (AllTasks, Upcoming,
 * Eisenhower, Kanban) had copy-pasted variants of the same four
 * `useMemo` blocks — search, filterList, filterPriority, filterTag —
 * with identical dependency arrays modulo controller naming. Folding
 * them into a single hook keeps the toolbar memoization contract
 * uniform: any view that wires the standard slots through this hook
 * gets identical re-render behaviour.
 *
 * The hook is intentionally oblivious to view-specific extras
 * (group-by, sort, view-mode toggles, horizon picker, "show completed"
 * — those are folded into `extraFilters` / `searchSuffix` / `trailing`
 * by each caller). It only standardizes the slots that are truly
 * universal across the four views.
 */
interface UseTaskListFilterSlotsArgs {
  search: string;
  setSearch: (value: string) => void;
  searchPlaceholder: string;
  lists: ListWithCount[];
  filterListId: string | null;
  setFilterListId: (value: string | null) => void;
  filterPriority: PriorityFilterValue;
  setFilterPriority: (value: PriorityFilterValue) => void;
  allTags: string[];
  selectedTags: Set<string>;
  toggleTag: (tag: string) => void;
  clearTagFilter: () => void;
}

export function useTaskListFilterSlots(args: UseTaskListFilterSlotsArgs) {
  const {
    search, setSearch, searchPlaceholder,
    lists, filterListId, setFilterListId,
    filterPriority, setFilterPriority,
    allTags, selectedTags, toggleTag, clearTagFilter,
  } = args;

  const searchSlot = useMemo(
    () => ({ value: search, onChange: setSearch, placeholder: searchPlaceholder }),
    [search, setSearch, searchPlaceholder],
  );
  const filterListSlot = useMemo(
    () => ({ lists, value: filterListId, onChange: setFilterListId }),
    [lists, filterListId, setFilterListId],
  );
  const filterPrioritySlot = useMemo(
    () => ({ value: filterPriority, onChange: setFilterPriority }),
    [filterPriority, setFilterPriority],
  );
  const filterTagSlot = useMemo(
    () => ({
      available: allTags,
      selected: selectedTags,
      onToggle: toggleTag,
      onClear: clearTagFilter,
    }),
    [allTags, selectedTags, toggleTag, clearTagFilter],
  );

  return { searchSlot, filterListSlot, filterPrioritySlot, filterTagSlot };
}
