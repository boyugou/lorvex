import { memo, type ReactNode } from 'react';
import type { ListWithCount } from '@/lib/ipc/tasks/models';
import { useI18n } from '@/lib/i18n';
import type { PriorityFilterValue } from '@/lib/tasks/priorityFilter';
import { FilterDropdown, type FilterOption } from './FilterDropdown';
import { ListFilterPills } from './ListFilterPills';
import { PriorityFilterDropdown } from './PriorityFilterDropdown';
import { SearchInput } from './SearchInput';
import { TagFilterPills } from './TagFilterPills';
import { Tooltip } from './Tooltip';

// ---------------------------------------------------------------------------
// Slot types — each is optional. The toolbar renders only the slots supplied.
//
// list-like views had diverged on which search/filter/sort
// affordances they exposed. ViewToolbar is the shared primitive that aligns
// the layout and behaviour so learning filters on one view carries over to
// the next. Controllers still own the state; this component is pure UI.
// ---------------------------------------------------------------------------

interface SortOption<K extends string> {
  value: K;
  label: string;
}

interface SearchSlot {
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
}

interface SortSlot<K extends string> {
  label?: string;
  value: K;
  options: SortOption<K>[];
  onChange: (value: K) => void;
  /** Optional sort-direction control. Hidden when `direction` is omitted. */
  direction?: 'asc' | 'desc';
  onToggleDirection?: () => void;
  /** If set, the direction toggle is hidden when `value === hideDirectionFor`. */
  hideDirectionFor?: K;
}

interface GroupSlot<K extends string> {
  label?: string;
  value: K;
  options: SortOption<K>[];
  onChange: (value: K) => void;
}

interface ListFilterSlot {
  lists: ListWithCount[];
  value: string | null;
  onChange: (value: string | null) => void;
}

interface TagFilterSlot {
  selected: Set<string>;
  onToggle: (tag: string) => void;
  onClear: () => void;
  available: string[];
}

interface PriorityFilterSlot {
  value: PriorityFilterValue;
  onChange: (value: PriorityFilterValue) => void;
}

export interface ViewToolbarProps<SortKey extends string = string, GroupKey extends string = string> {
  /** Search input slot. Rendered on its own row, above the filter row. */
  search?: SearchSlot;
  /** Content rendered next to the search input (e.g. result count). */
  searchSuffix?: ReactNode;
  /** Sort dropdown. */
  sort?: SortSlot<SortKey>;
  /** Group-by dropdown. */
  group?: GroupSlot<GroupKey>;
  /** List filter dropdown. */
  filterList?: ListFilterSlot;
  /** Priority filter dropdown. */
  filterPriority?: PriorityFilterSlot;
  /** Tag filter dropdown + pills. */
  filterTag?: TagFilterSlot;
  /** Additional filter/toggle controls (e.g. show completed, view mode). */
  extraFilters?: ReactNode;
  /** Trailing aligned controls (e.g. expand/collapse all). */
  trailing?: ReactNode;
}

function ViewToolbarInner<SortKey extends string = string, GroupKey extends string = string>({
  search,
  searchSuffix,
  sort,
  group,
  filterList,
  filterPriority,
  filterTag,
  extraFilters,
  trailing,
}: ViewToolbarProps<SortKey, GroupKey>) {
  const { t } = useI18n();

  const hasFilterRow =
    !!sort || !!group || !!filterList || !!filterPriority || !!filterTag || !!extraFilters || !!trailing;

  return (
    <>
      {search && (
        <div className="mt-4 flex items-center gap-3">
          <SearchInput
            value={search.value}
            onChange={search.onChange}
            placeholder={search.placeholder}
          />
          {searchSuffix}
        </div>
      )}
      {hasFilterRow && (
        <div className="flex items-center gap-2 mt-3 flex-wrap">
          {sort && (
            <FilterDropdown<SortKey>
              label={sort.label ?? t('allTasks.sortBy')}
              value={sort.value}
              options={sort.options as FilterOption<SortKey>[]}
              onChange={sort.onChange}
              trailingAction={
                sort.direction && sort.onToggleDirection && sort.value !== sort.hideDirectionFor ? (
                  <Tooltip
                    label={sort.direction === 'asc' ? t('allTasks.sortAsc') : t('allTasks.sortDesc')}
                  >
                    <button
                      type="button"
                      onClick={sort.onToggleDirection}
                      aria-label={sort.direction === 'asc' ? t('allTasks.sortAsc') : t('allTasks.sortDesc')}
                      className="text-xs px-1.5 py-1 rounded-r-control border border-accent/30 bg-accent/10 text-accent hover:border-accent/50 hover:bg-accent/15 focus-ring-soft transition-colors"
                    >
                      {sort.direction === 'asc' ? '↑' : '↓'}
                    </button>
                  </Tooltip>
                ) : undefined
              }
            />
          )}
          {group && (
            <FilterDropdown<GroupKey>
              label={group.label ?? t('allTasks.groupBy')}
              value={group.value}
              options={group.options as FilterOption<GroupKey>[]}
              onChange={group.onChange}
            />
          )}
          {filterList && (
            <ListFilterPills
              lists={filterList.lists}
              value={filterList.value}
              onChange={filterList.onChange}
            />
          )}
          {filterPriority && (
            <PriorityFilterDropdown
              value={filterPriority.value}
              onChange={filterPriority.onChange}
            />
          )}
          {filterTag && (
            <TagFilterPills
              tags={filterTag.available}
              selected={filterTag.selected}
              onToggle={filterTag.onToggle}
              onClear={filterTag.onClear}
            />
          )}
          {extraFilters}
          {trailing && <div className="ms-auto">{trailing}</div>}
        </div>
      )}
    </>
  );
}

// Wrap in `memo` so callers that hand us memoized config objects (search,
// sort, group, filterList, filterPriority, filterTag) actually skip the
// internal filter-dropdown re-render tree on every parent state tick.
// Generic identity is preserved by re-asserting the original signature —
// `memo` widens the type parameters to `unknown` otherwise.
export const ViewToolbar = memo(ViewToolbarInner) as typeof ViewToolbarInner;
