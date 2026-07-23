import { useI18n } from '@/lib/i18n';
import { formatNumber } from '@/locales';
import {
  formatListOpenTaskCountLabel,
  formatListRecentlyCompletedTaskCountLabel,
} from '@/lib/dates/i18nCountPhrases';

import { SORT_KEYS, type SortKey } from '../all-tasks/types';
import { formatDurationCompact } from '../today-view/primitives';
import { BulkActionBar } from '../ui/BulkActionBar';
import { ViewToolbar } from '../ui/ViewToolbar';

import { useListView } from './ListViewContext';

// ---------------------------------------------------------------------------
// Props (only values not available in context)
// ---------------------------------------------------------------------------

interface ListViewToolbarProps {
  totalEstimatedMinutes: number;
}

// ---------------------------------------------------------------------------
// Sort key label map
// ---------------------------------------------------------------------------

function useSortKeyLabels(): Record<SortKey, string> {
  const { t } = useI18n();
  return {
    default: t('allTasks.sortDefault'),
    dueDate: t('allTasks.sortDueDate'),
    plannedDate: t('allTasks.sortPlannedDate'),
    priority: t('allTasks.sortPriority'),
    actionDate: t('allTasks.sortActionDate'),
    completedAt: t('allTasks.sortCompletedAt'),
    createdAt: t('allTasks.sortCreatedAt'),
    title: t('allTasks.sortTitle'),
  };
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function ListViewToolbar({
  totalEstimatedMinutes,
}: ListViewToolbarProps): React.JSX.Element {
  const { locale, t, formatNumber: formatLocaleNumber } = useI18n();
  const {
    openTasks,
    completedTasks,
    search,
    onSearchChange,
    sortKey,
    sortDirection,
    onSortKeyChange,
    onToggleSortDirection,
    filterPriority,
    onFilterPriorityChange,
    allTags,
    selectedTags,
    onToggleTag,
    onClearTagFilter,
    isFilterActive,
    totalOpenCount,
    selectionMode,
    onSelectAll,
    onClearSelection,
    bulk,
  } = useListView();
  const sortLabels = useSortKeyLabels();

  const countLabel = isFilterActive
    ? `${formatNumber(locale, openTasks.length)} / ${formatListOpenTaskCountLabel(locale, totalOpenCount, t)}`
    : formatListOpenTaskCountLabel(locale, openTasks.length, t);

  const durationSuffix = totalEstimatedMinutes > 0
    ? ` · ${formatDurationCompact(totalEstimatedMinutes, t('common.hourShort'), t('common.min'), formatLocaleNumber)} ${t('common.estimated')}`
    : '';

  return (
    <>
      <ViewToolbar<SortKey>
        search={{ value: search, onChange: onSearchChange, placeholder: t('allTasks.search') }}
        searchSuffix={
          <span className="text-text-muted/70 text-xs">
            {countLabel} · {formatListRecentlyCompletedTaskCountLabel(locale, completedTasks.length, t)}{durationSuffix}
          </span>
        }
        sort={{
          value: sortKey,
          options: SORT_KEYS.map((key) => ({ value: key, label: sortLabels[key] })),
          onChange: onSortKeyChange,
          direction: sortDirection,
          onToggleDirection: onToggleSortDirection,
          hideDirectionFor: 'default' as SortKey,
        }}
        filterPriority={{ value: filterPriority, onChange: onFilterPriorityChange }}
        filterTag={{ available: allTags, selected: selectedTags, onToggle: onToggleTag, onClear: onClearTagFilter }}
      />

      {selectionMode && (
        <BulkActionBar
          selectedCount={bulk.selectedCount}
          bulkAction={bulk.bulkAction}
          onSelectAll={onSelectAll}
          onClearSelection={onClearSelection}
          onComplete={() => void bulk.handleBulkComplete()}
          onDefer={() => void bulk.handleBulkDefer()}
          onCancel={() => void bulk.handleBulkCancel()}
          onMove={(listId) => void bulk.handleBulkMove(listId)}
        />
      )}
    </>
  );
}
