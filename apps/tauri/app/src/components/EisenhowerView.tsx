import { useCallback, useMemo } from 'react';
import { useI18n } from '../lib/i18n';
import { useScrollRestore } from '../lib/useScrollRestore';
import { useRecentlyDroppedTask } from '../lib/useRecentlyDroppedTask';
import { formatDurationCompact } from './today-view/primitives';
import { SavedQueriesMenu } from './ui/SavedQueriesMenu';
import { HORIZON_OPTIONS, TimeHorizonPicker } from './ui/TimeHorizonPicker';
import {
  deserializeViewFilters,
  readSavedFilterNumberEnum,
  serializeViewFilters,
} from '../lib/tasks/savedFilterShape';
import { SearchIcon } from './ui/icons';
import { StaleDataBanner } from './ui/StaleDataBanner';
import { Tooltip } from './ui/Tooltip';
import { TaskBoardBodyState } from './task-board/TaskBoardBodyState';
import {
  QUADRANT_KEYS, QUADRANT_STYLE, URGENT_DAYS_THRESHOLD,
  type QuadrantKey,
} from './eisenhower/quadrants';
import { EisenhowerViewSkeleton } from './eisenhower/EisenhowerViewSkeleton';
import { useEisenhowerController } from './eisenhower/useEisenhowerController';
import { Quadrant } from './eisenhower/Quadrant';
import { AddTaskHeaderButton } from './task-list-view/AddTaskHeaderButton';
import { TaskListViewShell } from './task-list-view/TaskListViewShell';
import { useTaskListFilterSlots } from './task-list-view/useTaskListFilterSlots';

/**
 * i18n key suffixes for each quadrant's title + hint. Keyed by the
 * canonical `QuadrantKey` so the matrix render is a single map: adding
 * a fifth quadrant means appending one entry here and one to
 * `QUADRANT_KEYS` / `QUADRANT_STYLE`, never duplicating the ~17-prop
 * `<Quadrant>` JSX block.
 */
// `as const` preserves the literal i18n key strings — `controller.t()`
// is strongly typed against the localized key union, so widening to
// `string` here would be a type error at the call site.
const QUADRANT_LABEL_KEYS = {
  urgent_important: {
    title: 'eisenhower.urgentImportant',
    hint: 'eisenhower.urgentImportantHint',
    empty: 'eisenhower.emptyQ1',
  },
  not_urgent_important: {
    title: 'eisenhower.notUrgentImportant',
    hint: 'eisenhower.notUrgentImportantHint',
    empty: 'eisenhower.emptyQ2',
  },
  urgent_not_important: {
    title: 'eisenhower.urgentNotImportant',
    hint: 'eisenhower.urgentNotImportantHint',
    empty: 'eisenhower.emptyQ3',
  },
  not_urgent_not_important: {
    title: 'eisenhower.notUrgentNotImportant',
    hint: 'eisenhower.notUrgentNotImportantHint',
    empty: 'eisenhower.emptyQ4',
  },
} as const satisfies Record<QuadrantKey, { title: string; hint: string; empty: string }>;

interface Props {
  onSelectTask?: ((taskId: string) => void) | undefined;
  /**
   * Opens the QuickCapture overlay. Wired to the header "+ Add task"
   * button so Eisenhower matches the other entity-list views'
   * top-right add affordance.
   */
  onAddTask?: (() => void) | undefined;
}

export default function EisenhowerView({ onSelectTask, onAddTask }: Props) {
  const controller = useEisenhowerController({ onSelectTask });
  const { formatNumber, format } = useI18n();
  const scroll = useScrollRestore('eisenhower');
  // tag the just-moved card so it can render the
  // settle + afterglow choreography. The marker auto-clears after
  // ~700 ms, so we wrap `controller.handleDrop` rather than relying
  // on a side-effect tied to mutation completion timestamps.
  const recentlyDropped = useRecentlyDroppedTask();
  const handleDropWithSettle = useCallback(
    (quadrant: QuadrantKey, taskId: string) => {
      controller.handleDrop(quadrant, taskId);
      recentlyDropped.markDropped(taskId);
    },
    [controller, recentlyDropped],
  );

  // Standard search + filter slots — see `useTaskListFilterSlots`.
  const { searchSlot, filterListSlot, filterPrioritySlot, filterTagSlot } = useTaskListFilterSlots({
    search: controller.search,
    setSearch: controller.setSearch,
    searchPlaceholder: controller.t('common.filterTasks'),
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

  // Cross-cutting props shared by every quadrant in the matrix render.
  // Pulling these into one memoized object lets the JSX map body stay
  // uniform — only per-key props (`tasks`, `styleClass`, `isDragOver`,
  // title/hint) are computed inline. Memoized so unrelated state ticks
  // don't allocate a fresh shared-props object and force every quadrant
  // to re-render.
  // Depend on the specific stable methods/values we read (not the
  // whole controller, whose object identity churns each render).
  const quadrantSharedProps = useMemo(
    () => ({
      onSelectTask,
      isFocused: controller.keyboard.isFocused,
      focusedTaskId: controller.keyboard.focusedId,
      dropHint: controller.t('eisenhower.dropHere'),
      isBusy: controller.changePriorityPending,
      onDragOverQuadrant: controller.setDragOverQuadrant,
      onDrop: handleDropWithSettle,
      isRecentlyDropped: recentlyDropped.isRecent,
      hourUnit: controller.t('common.hourShort'),
      minUnit: controller.t('common.min'),
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [
      onSelectTask,
      controller.keyboard.isFocused,
      controller.keyboard.focusedId,
      controller.t,
      controller.changePriorityPending,
      controller.setDragOverQuadrant,
      handleDropWithSettle,
      recentlyDropped.isRecent,
    ],
  );

  return (
    <TaskListViewShell
      pageTitleKey="nav.eisenhower"
      headerContent={
        <>
          <p className="text-text-muted text-xs font-medium mb-1">{controller.t('eisenhower.title')}</p>
          <div className="flex items-baseline justify-between">
            <h2 className="text-text-primary text-2xl font-light">{controller.t('eisenhower.subtitle')}</h2>
            <div className="flex items-center gap-3">
              {/* ensure the chip clears the WCAG 2.5.5
                  24×24 minimum hit target (pre-fix it was ~16 px tall). */}
              {controller.allFlatTasks.length > 0 && (
                <button
                  type="button"
                  onClick={() => { void controller.handleCopyMatrix(); }}
                  disabled={controller.copying}
                  className="text-text-muted text-xs hover:text-text-secondary active:scale-[0.97] transition-[color,opacity,transform] disabled:opacity-50 rounded-r-control focus-ring-soft px-2 py-1.5 min-h-8 inline-flex items-center"
                >
                  {controller.copying ? controller.t('common.copying') : controller.t('eisenhower.copyMatrix')}
                </button>
              )}
              {onAddTask && (
                <AddTaskHeaderButton
                  labelKey="eisenhower.addTask"
                  tooltipKey="eisenhower.addTaskTooltip"
                  onClick={onAddTask}
                />
              )}
            </div>
          </div>
          <p className="text-text-muted text-xs mt-2">
            <Tooltip label={controller.t('eisenhower.thresholdExplain')}>
              <span>
                {/* Route through the locale-aware `format`
                    interpolator with `formatNumber` so the digit +
                    day-suffix render correctly per locale (the "d"
                    suffix must live inside the translation, not
                    outside it). */}
                {format('eisenhower.thresholdLine', {
                  days: formatNumber(URGENT_DAYS_THRESHOLD),
                })}
              </span>
            </Tooltip>
            {controller.totalDurationMinutes > 0 && (
              <span className="ms-3">
                · {formatNumber(controller.allFlatTasks.length)} {controller.t('eisenhower.tasksTotal')} · {formatDurationCompact(controller.totalDurationMinutes, controller.t('common.hourShort'), controller.t('common.min'), formatNumber)}
              </span>
            )}
          </p>
          {controller.allFlatTasks.length > 0 && (
            <p className="text-3xs text-text-muted/60 mt-1">
              {controller.t('eisenhower.dragHint')}
            </p>
          )}
        </>
      }
      toolbar={{
        search: searchSlot,
        filterList: filterListSlot,
        filterPriority: filterPrioritySlot,
        filterTag: filterTagSlot,
        extraFilters: (
          <>
            <TimeHorizonPicker value={controller.horizonDays} onChange={controller.setHorizonDays} />
            <SavedQueriesMenu
              viewType="Eisenhower"
              onCapture={() =>
                serializeViewFilters({
                  search: controller.search,
                  filterListId: controller.filterListId,
                  filterPriority: controller.filterPriority,
                  selectedTags: controller.selectedTags,
                  horizonDays: controller.horizonDays,
                })
              }
              onApply={(filterJson) => {
                const decoded = deserializeViewFilters(filterJson);
                controller.setSearch(decoded.search ?? '');
                controller.setFilterListId(decoded.listId ?? null);
                controller.setFilterPriority(decoded.priority ?? null);
                controller.replaceSelectedTags(decoded.tags ?? []);
                const nextHorizonDays = readSavedFilterNumberEnum(
                  decoded.horizonDays,
                  HORIZON_OPTIONS,
                );
                if (nextHorizonDays !== undefined) {
                  controller.setHorizonDays(nextHorizonDays);
                }
              }}
            />
          </>
        ),
      }}
      body={
        <div ref={scroll.ref} onScroll={scroll.onScroll} className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8">
          {/* show the stale-data banner when a background
              refetch fails but cached rows are still rendered. */}
          {controller.isError && controller.allFlatTasks.length > 0 && (
            <StaleDataBanner t={controller.t} onRetry={() => { void controller.refetch(); }} />
          )}
          <TaskBoardBodyState
            isLoading={controller.isLoading}
            isError={controller.isError}
            hasAnyData={controller.allFlatTasks.length > 0}
            isNoMatch={controller.allFlatTasks.length === 0 && controller.isFilterActive && controller.totalActiveCount > 0}
            loading={<EisenhowerViewSkeleton />}
            onRetry={() => { void controller.refetch(); }}
            noMatch={{
              icon: <SearchIcon className="w-9 h-9" />,
              title: controller.t('allTasks.emptyNoMatch'),
              subtitle: controller.t('allTasks.emptySearchHint'),
            }}
          >
            <div className="grid grid-cols-1 lg:grid-cols-2 lg:auto-rows-fr gap-4">
              {QUADRANT_KEYS.map((key) => (
                <Quadrant
                  key={key}
                  quadrantKey={key}
                  title={controller.t(QUADRANT_LABEL_KEYS[key].title)}
                  hint={controller.t(QUADRANT_LABEL_KEYS[key].hint)}
                  emptyLabel={controller.t(QUADRANT_LABEL_KEYS[key].empty)}
                  tasks={controller.quadrants[key]}
                  styleClass={QUADRANT_STYLE[key]}
                  isDragOver={controller.dragOverQuadrant === key}
                  {...quadrantSharedProps}
                />
              ))}
            </div>
          </TaskBoardBodyState>
        </div>
      }
      pickerTasks={controller.allFlatTasks}
      pickerActions={controller.actions}
    />
  );
}
