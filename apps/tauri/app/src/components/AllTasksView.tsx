import { useCallback, useEffect, useMemo, useRef, type MouseEvent as ReactMouseEvent } from 'react';
import { useI18n } from '../lib/i18n';
import { useScrollRestore } from '../lib/useScrollRestore';
import { useTaskListActions } from '../lib/tasks/useTaskListActions';
import { useTaskListKeyboard } from '../lib/tasks/useTaskListKeyboard';
import { BulkActionBar } from './ui/BulkActionBar';
import { Button } from './ui/Button';
import { SavedQueriesMenu } from './ui/SavedQueriesMenu';
import {
  deserializeViewFilters,
  readSavedFilterEnum,
  serializeViewFilters,
} from '../lib/tasks/savedFilterShape';
import { ClipboardIcon, SearchIcon } from './ui/icons';
import { TaskBoardBodyState } from './task-board/TaskBoardBodyState';
import {
  useVirtualizedTaskRows,
  type VirtualizedSectionRow,
} from './list-view/virtualization';
import { AllTasksViewSkeleton } from './all-tasks/AllTasksViewSkeleton';
import { GROUP_BY_KEYS, SORT_KEYS, type GroupBy, type SortKey } from './all-tasks/types';
import { type AllTasksViewProps, useAllTasksController } from './all-tasks/useAllTasksController';
import { Header } from './all-tasks/Header';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TaskSection } from './all-tasks/types';
import {
  HEADER_HEIGHT,
  SECTION_GAP_HEIGHT,
  SectionRow,
  TASK_ROW_HEIGHT,
} from './all-tasks/Section';

// ---------------------------------------------------------------------------
// Virtual row types — payloads carried by the AllTasks virtualized body. The
// rich union keeps section + task data attached for the JSX render, while a
// narrower projection feeds the shared `useVirtualizedTaskRows` hook.
// ---------------------------------------------------------------------------

export interface VirtualSectionHeaderRow {
  kind: 'section-header';
  section: TaskSection;
  collapsed: boolean;
}

export interface VirtualTaskRow {
  kind: 'task';
  task: Task;
  completed?: boolean | undefined;
}

/** Spacer between sections for visual grouping. */
export interface VirtualSectionGapRow {
  kind: 'section-gap';
}

export type VirtualRow = VirtualSectionHeaderRow | VirtualTaskRow | VirtualSectionGapRow;
import { KeyboardHintBar } from './ui/KeyboardHintBar';
import { TaskListViewShell } from './task-list-view/TaskListViewShell';
import { useTaskListFilterSlots } from './task-list-view/useTaskListFilterSlots';

export default function AllTasksView(props: AllTasksViewProps) {
  const { locale, t } = useI18n();
  const scroll = useScrollRestore('all-tasks');
  const controller = useAllTasksController(props.initialSearch);

  const allTasks = useMemo(
    () => controller.sections.flatMap((s) =>
      controller.collapsedSections.has(s.key) ? [] : s.tasks,
    ),
    [controller.sections, controller.collapsedSections],
  );
  const allTaskIds = useMemo(() => allTasks.map((tk) => tk.id), [allTasks]);
  const baseActions = useTaskListActions(allTasks);

  const onExtendSelection = useCallback(
    (direction: 'up' | 'down', focusedId: string | null) =>
      controller.handleKeyboardExtend(direction, allTaskIds, focusedId),
    [controller, allTaskIds],
  );
  const onClickWithModifiers = useCallback(
    (id: string, event: ReactMouseEvent<HTMLButtonElement>) =>
      controller.handleClickWithModifiers(id, event, allTaskIds, null),
    [controller, allTaskIds],
  );
  const actions = {
    ...baseActions,
    onToggleSelected: controller.toggleTaskSelected,
    setSelectionModeEnabled: controller.setSelectionModeEnabled,
    selectionModeActive: controller.selectionMode,
    onExtendSelection,
    onSelectAll: controller.selectAll,
    onClearSelection: controller.clearSelection,
    hasSelection: controller.selectedIds.size > 0,
  };
  const keyboard = useTaskListKeyboard({
    taskIds: allTaskIds,
    onSelect: props.onSelectTask,
    actions,
    disabled: controller.isLoading,
  });

  // ── Virtual rows ────────────────────────────────────────────────────
  const virtualRows = useMemo<VirtualRow[]>(() => {
    const rows: VirtualRow[] = [];
    controller.sections.forEach((section, sIdx) => {
      if (sIdx > 0) rows.push({ kind: 'section-gap' });
      const collapsed = controller.collapsedSections.has(section.key);
      rows.push({ kind: 'section-header', section, collapsed });
      if (!collapsed) {
        for (const task of section.tasks) {
          rows.push({ kind: 'task', task, completed: section.completed });
        }
      }
    });
    return rows;
  }, [controller.sections, controller.collapsedSections]);

  // Project the rich `VirtualRow[]` (which carries section + task
  // payloads for the JSX render) down to the narrow tagged-union the
  // shared `useVirtualizedTaskRows` hook understands. Memoized so the
  // hook's effect dependencies stay stable across renders that don't
  // change the row sequence.
  const virtualizerRows = useMemo<VirtualizedSectionRow[]>(
    () => virtualRows.map((row) =>
      row.kind === 'task'
        ? { kind: 'task', taskId: row.task.id }
        : { kind: row.kind },
    ),
    [virtualRows],
  );

  const parentRef = useRef<HTMLDivElement>(null);

  const mergedRef = useCallback(
    (node: HTMLDivElement | null) => {
      (parentRef as React.MutableRefObject<HTMLDivElement | null>).current = node;
      (scroll.ref as React.MutableRefObject<HTMLDivElement | null>).current = node;
    },
    [scroll.ref],
  );

  // Section-aware virtualizer with per-task id-keyed height
  // cache. See `useVirtualizedTaskRows` for the rationale — folded out
  // of the bespoke AllTasksView setup so any tuning lives next to the
  // simpler `useVirtualizedTaskColumn` helper used by Eisenhower / Kanban.
  const { virtualItems, totalSize, measureElement } = useVirtualizedTaskRows({
    rows: virtualizerRows,
    scrollRef: parentRef,
    headerHeight: HEADER_HEIGHT,
    sectionGapHeight: SECTION_GAP_HEIGHT,
    taskRowEstimate: TASK_ROW_HEIGHT,
    focusedTaskId: keyboard.focusedId,
  });

  // Stable per-section toggle handler factory. Without this each
  // virtual render minted a fresh `() => controller.toggleSectionCollapse(key)`
  // for every header row, which defeated `VirtualSectionHeader`'s
  // `memo` boundary on every virtualizer state tick. The outer
  // `useCallback` is keyed on the (already-stable) controller method
  // and the inner closure captures `sectionKey` per call site, so two
  // headers with the same key reuse the same handler reference across
  // renders.
  const sectionToggleHandlersRef = useRef(new Map<string, () => void>());
  // Depend on the stable `.toggleSectionCollapse` method only (not the
  // whole controller bag, whose identity churns each render).
  const getSectionToggleHandler = useCallback(
    (sectionKey: string): (() => void) => {
      const cache = sectionToggleHandlersRef.current;
      const cached = cache.get(sectionKey);
      if (cached) return cached;
      const handler = () => controller.toggleSectionCollapse(sectionKey);
      cache.set(sectionKey, handler);
      return handler;
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [controller.toggleSectionCollapse],
  );
  // Reset the cache whenever the underlying toggler changes so we don't
  // hold a closure over a stale `controller.toggleSectionCollapse`.
  useEffect(() => {
    sectionToggleHandlersRef.current = new Map();
  }, [controller.toggleSectionCollapse]);

  const sortLabels = useMemo<Record<SortKey, string>>(() => ({
    default: t('allTasks.sortDefault'),
    dueDate: t('allTasks.sortDueDate'),
    plannedDate: t('allTasks.sortPlannedDate'),
    priority: t('allTasks.sortPriority'),
    actionDate: t('allTasks.sortActionDate'),
    completedAt: t('allTasks.sortCompletedAt'),
    createdAt: t('allTasks.sortCreatedAt'),
    title: t('allTasks.sortTitle'),
  }), [t]);

  const groupByLabels = useMemo<Record<GroupBy, string>>(() => ({
    status: t('allTasks.groupByStatus'),
    list: t('allTasks.groupByList'),
    due_date: t('allTasks.groupByDueDate'),
    priority: t('allTasks.groupByPriority'),
    tag: t('allTasks.groupByTag'),
  }), [t]);

  // Standard search + filter slots — see `useTaskListFilterSlots`.
  const { searchSlot, filterListSlot, filterPrioritySlot, filterTagSlot } = useTaskListFilterSlots({
    search: controller.search,
    setSearch: controller.setSearch,
    searchPlaceholder: t('allTasks.search'),
    lists: controller.lists,
    filterListId: controller.filterListId,
    setFilterListId: controller.setFilterListId,
    filterPriority: controller.filterPriority,
    setFilterPriority: controller.setFilterPriority,
    allTags: controller.allTags,
    selectedTags: controller.selectedTags,
    toggleTag: controller.toggleTag,
    clearTagFilter: controller.clearTagFilter,
  });
  const groupSlot = useMemo(
    () => ({
      value: controller.groupBy,
      options: GROUP_BY_KEYS.map((key) => ({ value: key, label: groupByLabels[key] })),
      onChange: controller.setGroupBy,
    }),
    [controller.groupBy, controller.setGroupBy, groupByLabels],
  );
  const sortSlot = useMemo(
    () => ({
      value: controller.sortKey,
      options: SORT_KEYS.map((key) => ({ value: key, label: sortLabels[key] })),
      onChange: controller.setSortKey,
      direction: controller.sortDirection,
      onToggleDirection: controller.toggleSortDirection,
      hideDirectionFor: 'default' as SortKey,
    }),
    [
      controller.sortKey,
      controller.setSortKey,
      controller.sortDirection,
      controller.toggleSortDirection,
      sortLabels,
    ],
  );

  return (
    <TaskListViewShell<SortKey, GroupBy>
      pageTitleKey="nav.allTasks"
      headerContent={
        <Header
          locale={locale}
          t={t}
          tasksLen={controller.tasks.length}
          totalCount={controller.totalCount}
          hasActiveFilter={controller.hasActiveFilter}
          onAddTask={props.onAddTask}
        />
      }
      toolbar={{
        search: searchSlot,
        searchSuffix: (
          <Button
            variant="outline"
            onClick={() => controller.setSelectionModeEnabled(!controller.selectionMode)}
            disabled={controller.bulkAction !== null}
          >
            {controller.selectionMode ? t('common.done') : t('allTasks.select')}
          </Button>
        ),
        group: groupSlot,
        sort: sortSlot,
        filterList: filterListSlot,
        filterPriority: filterPrioritySlot,
        filterTag: filterTagSlot,
        extraFilters: (
          <>
            <SavedQueriesMenu
              viewType="AllTasks"
              onCapture={() =>
                serializeViewFilters({
                  search: controller.search,
                  filterListId: controller.filterListId,
                  filterPriority: controller.filterPriority,
                  selectedTags: controller.selectedTags,
                  showCompleted: controller.showCompleted,
                  showCancelled: controller.showCancelled,
                  groupBy: controller.groupBy,
                  sortKey: controller.sortKey,
                  sortDirection: controller.sortDirection,
                })
              }
              onApply={(filterJson) => {
                // reapplying a preset resets the view's
                // filter pills + search + group/sort to the stored
                // snapshot. Missing fields fall back to "no filter"
                // so a payload saved by a narrower view decodes into
                // a wider one without nulling out unrelated controls.
                const decoded = deserializeViewFilters(filterJson);
                controller.setSearch(decoded.search ?? '');
                controller.setFilterListId(decoded.listId ?? null);
                controller.setFilterPriority(decoded.priority ?? null);
                controller.replaceSelectedTags(decoded.tags ?? []);
                if (decoded.showCompleted !== undefined)
                  controller.setShowCompleted(decoded.showCompleted);
                if (decoded.showCancelled !== undefined)
                  controller.setShowCancelled(decoded.showCancelled);
                const nextGroupBy = readSavedFilterEnum(decoded.groupBy, GROUP_BY_KEYS);
                if (nextGroupBy) controller.setGroupBy(nextGroupBy);
                const nextSortKey = readSavedFilterEnum(decoded.sortKey, SORT_KEYS);
                if (nextSortKey) controller.setSortKey(nextSortKey);
                const nextSortDirection = readSavedFilterEnum(
                  decoded.sortDirection,
                  ['asc', 'desc'] as const,
                );
                if (nextSortDirection) {
                  controller.setSortDirection(nextSortDirection);
                }
              }}
            />
            <button
              type="button"
              onClick={() => controller.setShowCompleted(!controller.showCompleted)}
              aria-pressed={controller.showCompleted}
              className={`text-xs px-2.5 py-1.5 rounded-r-card border transition-colors focus-ring-soft ${
                controller.showCompleted
                  ? 'bg-[var(--accent-tint-sm)] border-accent/40 text-accent'
                  : 'bg-surface-2 border-surface-3 text-text-secondary hover:bg-surface-3 hover:text-text-primary'
              }`}
            >
              {t('allTasks.showCompleted')}
            </button>
            <button
              type="button"
              onClick={() => controller.setShowCancelled(!controller.showCancelled)}
              aria-pressed={controller.showCancelled}
              className={`text-xs px-2.5 py-1.5 rounded-r-card border transition-colors focus-ring-soft ${
                controller.showCancelled
                  ? 'bg-[var(--accent-tint-sm)] border-accent/40 text-accent'
                  : 'bg-surface-2 border-surface-3 text-text-secondary hover:bg-surface-3 hover:text-text-primary'
              }`}
            >
              {t('allTasks.showCancelled')}
            </button>
          </>
        ),
        trailing:
          controller.sections.length > 1 ? (
            <button
              type="button"
              onClick={() => {
                const allCollapsed = controller.sections.every((s) => controller.collapsedSections.has(s.key));
                if (allCollapsed) {
                  controller.expandAllSections();
                } else {
                  controller.collapseAllSections(controller.sections.map((s) => s.key));
                }
              }}
              className="text-text-muted text-xs hover:text-text-secondary transition-colors focus-ring-soft rounded-r-control px-1"
            >
              {controller.sections.every((s) => controller.collapsedSections.has(s.key))
                ? t('common.expandAll')
                : t('common.collapseAll')}
            </button>
          ) : undefined,
      }}
      bulkBar={
        controller.selectionMode ? (
          <BulkActionBar
            selectedCount={controller.selectedCount}
            bulkAction={controller.bulkAction}
            onSelectAll={() => controller.selectAll()}
            onClearSelection={() => controller.setSelectedIds(new Set())}
            onComplete={() => void controller.handleBulkComplete()}
            onDefer={() => void controller.handleBulkDefer()}
            onCancel={() => void controller.handleBulkCancel()}
            onMove={(listId) => void controller.handleBulkMove(listId)}
          />
        ) : undefined
      }
      body={
        <div ref={mergedRef} onScroll={scroll.onScroll} className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8">
          <TaskBoardBodyState
            isLoading={controller.isLoading}
            isError={controller.isAllTasksError}
            hasAnyData={controller.tasks.length > 0}
            loading={<AllTasksViewSkeleton />}
            onRetry={() => { void controller.refetchAllTasks(); }}
            errorTitle={t('allTasks.loadFailed')}
            errorSubtitle={t('allTasks.loadFailedHint')}
            empty={{
              icon: controller.hasActiveFilter ? <SearchIcon className="w-9 h-9" /> : <ClipboardIcon className="w-9 h-9" />,
              title: controller.emptyTitleLabel,
              subtitle: controller.emptyHintLabel,
            }}
          >
            <div
              style={{ height: `${totalSize}px`, width: '100%', position: 'relative' }}
            >
              {virtualItems.map((virtualItem) => {
                const row = virtualRows[virtualItem.index];
                if (!row) return null;

                return (
                  <div
                    key={virtualItem.key}
                    data-index={virtualItem.index}
                    ref={measureElement}
                    style={{
                      position: 'absolute',
                      top: 0,
                      left: 0,
                      width: '100%',
                      transform: `translateY(${virtualItem.start}px)`,
                    }}
                  >
                    <SectionRow
                      row={row}
                      selectionMode={controller.selectionMode}
                      selectedIds={controller.selectedIds}
                      bulkAction={controller.bulkAction}
                      focusedId={keyboard.focusedId}
                      onSelectTask={props.onSelectTask}
                      onToggleSelected={controller.toggleTaskSelected}
                      onClickWithModifiers={onClickWithModifiers}
                      getSectionToggleHandler={getSectionToggleHandler}
                    />
                  </div>
                );
              })}
            </div>
          </TaskBoardBodyState>
          <KeyboardHintBar visible={keyboard.showKeyboardHints} />
        </div>
      }
      pickerTasks={allTasks}
      pickerActions={baseActions}
    />
  );
}
