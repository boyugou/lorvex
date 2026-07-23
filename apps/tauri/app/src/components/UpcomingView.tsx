import { useCallback, useMemo } from 'react';
import { BulkActionBar } from './ui/BulkActionBar';
import { SavedQueriesMenu } from './ui/SavedQueriesMenu';
import {
  deserializeViewFilters,
  readSavedFilterEnum,
  serializeViewFilters,
} from '../lib/tasks/savedFilterShape';
import { formatDurationCompact } from './today-view/primitives';
import WeekTimeline from './upcoming/WeekTimeline';
import { CalendarUpcomingIcon, WarningIcon } from './ui/icons';
import ModuleStatePanel from './ui/ModuleStatePanel';
import { StaleDataBanner } from './ui/StaleDataBanner';
import type { SortKey } from './all-tasks/types';
import { useUpcomingController, OVERDUE_KEY, UPCOMING_SORT_KEYS } from './upcoming/useUpcomingController';
import { KeyboardHintBar } from './ui/KeyboardHintBar';
import { UpcomingViewSkeleton } from './upcoming/UpcomingViewSkeleton';
import { formatNumber } from '../locales';
import {
  formatEventCountLabel,
  formatTaskCountLabel,
} from '../lib/dates/i18nCountPhrases';
import { AddTaskHeaderButton } from './task-list-view/AddTaskHeaderButton';
import { TaskListViewShell } from './task-list-view/TaskListViewShell';
import { useTaskListFilterSlots } from './task-list-view/useTaskListFilterSlots';
import { Banner } from './ui/Banner';
import { Button } from './ui/Button';
import { Overdue } from './upcoming/Sections/Overdue';
import { Today } from './upcoming/Sections/Today';
import { Week } from './upcoming/Sections/Week';
import { Later } from './upcoming/Sections/Later';
import { groupFutureDates } from './upcoming/Sections/futureDateGroups';

interface Props {
  onSelectTask?: ((taskId: string) => void) | undefined;
  /**
   * Opens the QuickCapture overlay. Wired to the header "+ Add task"
   * button so every entity-list view offers a consistent, top-right
   * add-entry point in addition to the global ⌘N shortcut.
   */
  onAddTask?: (() => void) | undefined;
}

const MODE_BUTTON_BASE = 'px-2 py-1 text-xs rounded-r-control transition-colors focus-ring-soft';

export default function UpcomingView({ onSelectTask, onAddTask }: Props) {
  const controller = useUpcomingController({ onSelectTask });

  const {
    t, locale, dayContext, scroll,
    viewMode, setViewMode,
    search, setSearch,
    filterPriority, setFilterPriority,
    sortKey, setSortKey,
    filterListId, setFilterListId,
    selectedTags, toggleTag, clearTagFilter, allTags,
    collapsedDates, toggleDateCollapse, collapseAllDates, expandAllDates,
    dragOverDate, setDragOverDate,
    nowHHMM, weekDates,
    tasks, events, lists,
    isTasksLoading, isTasksError, isEventsError,
    refetchTasks, refetchEvents,
    filteredTasks, groupedTasks, groupedEvents,
    allDates, futureDates, overdueTasks,
    totalEstimatedMinutes, overdueMinutes,
    isEmpty, isFilterActive,
    copying, handleCopyWeekPlan,
    allTaskIds, allCollapsibleKeys, keyboard,
    selectionMode, selectedIds, selectAll,
    toggleTaskSelected, setSelectionModeEnabled, setSelectedIds,
    onClickWithModifiers,
    bulk, actions, handleRescheduleTask,
  } = controller;
  const hasSelection = selectedIds.size > 0;

  // Stable handler keeps memoized `UpcomingTaskRow` instances from
  // re-rendering on every `dragOverDate` tick.
  const handleDragEnd = useCallback(() => setDragOverDate(null), [setDragOverDate]);

  // Sync wrapper for keyboard reschedule. The controller's
  // `handleRescheduleTask` returns a Promise (it `await`s the IPC
  // round-trip + invalidation), but the row's keydown handler is a
  // void-returning React event handler. Fire-and-forget here so the
  // row prop stays a clean `(id, date) => void`.
  const handleRowReschedule = useCallback(
    (taskId: string, newDate: string) => { void handleRescheduleTask(taskId, newDate); },
    [handleRescheduleTask],
  );

  // Partition future dates once per render so each Section component
  // only walks its own slice.
  const futureGroups = useMemo(
    () => groupFutureDates(futureDates, dayContext.todayYmd),
    [futureDates, dayContext.todayYmd],
  );

  // Standard search + filter slots — see `useTaskListFilterSlots`.
  const { searchSlot, filterListSlot, filterPrioritySlot, filterTagSlot } = useTaskListFilterSlots({
    search, setSearch,
    searchPlaceholder: t('upcoming.searchPlaceholder'),
    lists, filterListId, setFilterListId,
    filterPriority, setFilterPriority,
    allTags, selectedTags, toggleTag, clearTagFilter,
  });
  // The sort slot here is Upcoming-specific (its sort options are a
  // narrower subset than AllTasks's), so it stays inline rather than
  // routing through `useTaskListFilterSlots`.
  const sortSlot = {
    value: sortKey,
    options: UPCOMING_SORT_KEYS.map((key) => ({
      value: key,
      label: key === 'default' ? t('allTasks.sortDefault') : key === 'priority' ? t('allTasks.sortPriority') : t('allTasks.sortActionDate'),
    })),
    onChange: setSortKey,
  };

  // Stale-data banner: tasks-error takes priority over events-error
  // when both fire at once so the user sees the more disruptive
  // failure first. Each has its own retry callback.
  const staleBanner = (isTasksError && tasks.length > 0) ? (
    <div className="px-4 sm:px-8 pt-2">
      <StaleDataBanner t={t} onRetry={() => { void refetchTasks(); }} />
    </div>
  ) : (isEventsError && events.length > 0) ? (
    <div className="px-4 sm:px-8 pt-2">
      <StaleDataBanner t={t} onRetry={() => { void refetchEvents(); }} />
    </div>
  ) : undefined;

  const sectionContext = {
    groupedTasks,
    groupedEvents,
    collapsedDates,
    dragOverDate,
    toggleDateCollapse,
    setDragOverDate,
    handleRescheduleTask,
    onSelectTask,
    onClickWithModifiers,
    onDragEnd: handleDragEnd,
    selectionMode,
    selectedIds,
    bulkBusy: bulk.bulkAction !== null,
    focusedId: keyboard.focusedId,
    hasSelection,
    onToggleSelected: toggleTaskSelected,
    dayContext,
    nowHHMM,
    locale,
    t,
  };

  return (
    <TaskListViewShell<SortKey>
      pageTitleKey="nav.upcoming"
      headerContent={
        <div className="flex items-baseline justify-between">
          <div>
            <h2 className="text-text-primary text-2xl font-light">{t('upcoming.title')}</h2>
            <p className="text-text-muted text-xs mt-2">
              {formatTaskCountLabel(locale, filteredTasks.length, t)}
              {search && filteredTasks.length !== tasks.length && ` / ${formatNumber(locale, tasks.length)}`}
              {events.length > 0 && ` · ${formatEventCountLabel(locale, events.length, t)}`}
              {totalEstimatedMinutes > 0 && ` · ${formatDurationCompact(totalEstimatedMinutes, t('common.hourShort'), t('common.min'), (value) => formatNumber(locale, value))} ${t('common.estimated')}`}
            </p>
          </div>
          {/*
           * header "+ Add task" button. Aligns the
           * add-entry-point with the Calendar view's top-right "+ New
           * Event" and every other entity-list view. Routes to the
           * same QuickCapture overlay as ⌘N so there is exactly one
           * canonical creation surface; the inline input at the top
           * of the list stays as a faster shortcut.
           */}
          <div className="flex items-center gap-2">
            {onAddTask && (
              <AddTaskHeaderButton
                labelKey="upcoming.addTask"
                tooltipKey="upcoming.addTaskTooltip"
                onClick={onAddTask}
              />
            )}
            {!isEmpty && (
              <>
                {/* bump padding to clear the WCAG
                    2.5.5 24×24 minimum hit target — pre-fix this
                    bare-text chip was ~16 px tall. */}
                {(filteredTasks.length > 0 || events.length > 0) && (
                  <button
                    type="button"
                    onClick={() => { void handleCopyWeekPlan(); }}
                    disabled={copying}
                    className="text-text-muted text-xs hover:text-text-secondary transition-colors disabled:opacity-50 rounded-r-control focus-ring-soft px-2 py-1.5 min-h-8 inline-flex items-center"
                  >
                    {copying ? t('common.copying') : t('upcoming.copyWeekPlan')}
                  </button>
                )}
                {viewMode === 'list' && allDates.length > 1 && (
                  <button
                    type="button"
                    onClick={() => {
                      const allCollapsed = allCollapsibleKeys.every((d) => collapsedDates.has(d));
                      if (allCollapsed) expandAllDates();
                      else collapseAllDates(allCollapsibleKeys);
                    }}
                    className="text-text-muted text-xs hover:text-text-secondary transition-colors rounded-r-control focus-ring-soft px-2 py-1.5 min-h-8 inline-flex items-center"
                  >
                    {allCollapsibleKeys.every((d) => collapsedDates.has(d))
                      ? t('common.expandAll')
                      : t('common.collapseAll')}
                  </button>
                )}
                {viewMode === 'list' && allTaskIds.length > 0 && (
                  <Button
                    variant="outline"
                    onClick={() => setSelectionModeEnabled(!selectionMode)}
                    disabled={bulk.bulkAction !== null}
                  >
                    {selectionMode ? t('common.done') : t('allTasks.select')}
                  </Button>
                )}
                <div className="flex gap-1 bg-surface-2 rounded-r-card p-0.5">
                  <button
                    type="button"
                    onClick={() => setViewMode('list')}
                    className={`${MODE_BUTTON_BASE} ${viewMode === 'list' ? 'bg-surface-3 text-text-primary' : 'text-text-muted hover:text-text-secondary'}`}
                    aria-pressed={viewMode === 'list'}
                  >
                    {t('upcoming.listView')}
                  </button>
                  <button
                    type="button"
                    onClick={() => { setViewMode('timeline'); setSelectionModeEnabled(false); }}
                    className={`${MODE_BUTTON_BASE} ${viewMode === 'timeline' ? 'bg-surface-3 text-text-primary' : 'text-text-muted hover:text-text-secondary'}`}
                    aria-pressed={viewMode === 'timeline'}
                  >
                    {t('upcoming.timelineView')}
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      }
      toolbar={{
        search: searchSlot,
        sort: sortSlot,
        filterList: filterListSlot,
        filterPriority: filterPrioritySlot,
        filterTag: filterTagSlot,
        trailing: (
          <SavedQueriesMenu
            viewType="Upcoming"
            onCapture={() =>
              serializeViewFilters({
                search,
                filterListId,
                filterPriority,
                selectedTags,
                sortKey,
              })
            }
            onApply={(filterJson) => {
              const decoded = deserializeViewFilters(filterJson);
              setSearch(decoded.search ?? '');
              setFilterListId(decoded.listId ?? null);
              setFilterPriority(decoded.priority ?? null);
              controller.replaceSelectedTags(decoded.tags ?? []);
              const nextSortKey = readSavedFilterEnum(decoded.sortKey, UPCOMING_SORT_KEYS);
              if (nextSortKey) setSortKey(nextSortKey);
            }}
          />
        ),
      }}
      bulkBar={
        selectionMode ? (
          <BulkActionBar
            selectedCount={bulk.selectedCount}
            bulkAction={bulk.bulkAction}
            onSelectAll={selectAll}
            onClearSelection={() => setSelectedIds(new Set())}
            onComplete={() => void bulk.handleBulkComplete()}
            onDefer={() => void bulk.handleBulkDefer()}
            onCancel={() => void bulk.handleBulkCancel()}
            onMove={(listId) => void bulk.handleBulkMove(listId)}
          />
        ) : undefined
      }
      staleBanner={staleBanner}
      body={
        isTasksLoading ? (
          <div className="flex-1 px-4 sm:px-8 pb-8"><UpcomingViewSkeleton /></div>
        ) : isTasksError && tasks.length === 0 ? (
          <div className="flex-1 px-4 sm:px-8 pb-8">
            <ModuleStatePanel
              variant="error"
              icon={<WarningIcon className="w-9 h-9" />}
              title={t('common.error')}
              actionLabel={t('error.tryAgain')}
              onAction={() => { void refetchTasks(); }}
            />
          </div>
        ) : isEventsError && events.length === 0 && tasks.length === 0 ? (
          <div className="flex-1 px-4 sm:px-8 pb-8">
            <ModuleStatePanel
              variant="error"
              icon={<WarningIcon className="w-9 h-9" />}
              title={t('common.error')}
              actionLabel={t('error.tryAgain')}
              onAction={() => { void refetchEvents(); }}
            />
          </div>
        ) : isEmpty ? (
          <div className="flex-1 px-4 sm:px-8 pb-8">
            <ModuleStatePanel
              icon={<CalendarUpcomingIcon className="w-9 h-9" />}
              title={t('upcoming.empty')}
              subtitle={isFilterActive && tasks.length > 0 ? t('upcoming.noFilterResults') : t('upcoming.emptyHint')}
              // When filters are hiding everything, give the
              // user a one-click reset instead of leaving them to
              // unwind each filter manually. Drops search, list,
              // priority, and tag filters in one go.
              {...(isFilterActive && tasks.length > 0
                ? {
                    actionLabel: t('common.clearFilters'),
                    onAction: () => {
                      setSearch('');
                      setFilterListId(null);
                      setFilterPriority(null);
                      clearTagFilter();
                    },
                  }
                : {})}
            />
          </div>
        ) : viewMode === 'timeline' ? (
          <div className="flex-1 min-h-0 px-4 pb-4">
            {isEventsError && (
              <Banner
                tone="warning"
                density="cozy"
                className="mb-2"
                actions={
                  <button
                    type="button"
                    onClick={() => { void refetchEvents(); }}
                    className="text-warning hover:text-warning/80 underline text-xs rounded-r-control focus-ring-soft-warning"
                  >
                    {t('error.tryAgain')}
                  </button>
                }
              >
                {t('upcoming.eventsLoadError')}
              </Banner>
            )}
            <WeekTimeline
              weekDates={weekDates}
              tasksByDate={groupedTasks}
              eventsByDate={groupedEvents}
              today={dayContext.todayYmd}
              locale={locale}
              t={t}
              onSelectTask={onSelectTask}
            />
          </div>
        ) : (
          <div ref={scroll.ref} onScroll={scroll.onScroll} className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8 space-y-6">
            {isEventsError && (
              <Banner
                tone="warning"
                density="cozy"
                className="mb-4"
                actions={
                  <button
                    type="button"
                    onClick={() => { void refetchEvents(); }}
                    className="text-warning hover:text-warning/80 underline text-xs rounded-r-control focus-ring-soft-warning"
                  >
                    {t('error.tryAgain')}
                  </button>
                }
              >
                {t('upcoming.eventsLoadError')}
              </Banner>
            )}
            {overdueTasks.length > 0 && (
              <Overdue
                tasks={overdueTasks}
                totalMinutes={overdueMinutes}
                collapsed={collapsedDates.has(OVERDUE_KEY)}
                onToggleCollapse={() => toggleDateCollapse(OVERDUE_KEY)}
                selectionMode={selectionMode}
                selectedIds={selectedIds}
                bulkBusy={bulk.bulkAction !== null}
                focusedId={keyboard.focusedId}
                hasSelection={hasSelection}
                onToggleSelected={toggleTaskSelected}
                onSelectTask={onSelectTask}
                onClickWithModifiers={onClickWithModifiers}
                onRescheduleTask={handleRowReschedule}
                onDragEnd={handleDragEnd}
                locale={locale}
                t={t}
              />
            )}
            <Today dates={futureGroups.today} {...sectionContext} />
            <Week dates={futureGroups.week} {...sectionContext} />
            <Later dates={futureGroups.later} {...sectionContext} />
            <KeyboardHintBar visible={keyboard.showKeyboardHints} />
          </div>
        )
      }
      pickerTasks={filteredTasks}
      pickerActions={actions}
    />
  );
}
