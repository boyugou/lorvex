import { useI18n } from '../lib/i18n';
import { formatTaskCountLabel } from '../lib/dates/i18nCountPhrases';
import { useRuntimeProfile } from '../lib/useRuntimeProfile';
import { useScrollRestore } from '../lib/useScrollRestore';
import { Toggle } from './ui/Toggle';
import { SearchIcon } from './ui/icons';
import { StaleDataBanner } from './ui/StaleDataBanner';
import { TaskBoardBodyState } from './task-board/TaskBoardBodyState';
import { HORIZON_OPTIONS, TimeHorizonPicker } from './ui/TimeHorizonPicker';
import { SavedQueriesMenu } from './ui/SavedQueriesMenu';
import {
  deserializeViewFilters,
  readSavedFilterNumberEnum,
  serializeViewFilters,
} from '../lib/tasks/savedFilterShape';
import {
  COLUMN_LABEL_KEYS, COLUMN_STYLE,
} from './kanban/columns';
import KanbanMobileView from './kanban/KanbanMobileView';
import { KanbanViewSkeleton } from './kanban/KanbanViewSkeleton';
import { useKanbanController } from './kanban/useKanbanController';
import { Column } from './kanban/Column';
import { AddTaskHeaderButton } from './task-list-view/AddTaskHeaderButton';
import { TaskListViewShell } from './task-list-view/TaskListViewShell';
import { useTaskListFilterSlots } from './task-list-view/useTaskListFilterSlots';

interface Props {
  onSelectTask?: ((taskId: string) => void) | undefined;
  /**
   * Opens QuickCapture for the "+ Add task" header button. Receives
   * the Kanban list-filter so the new task can be pre-assigned to the
   * list the user is currently viewing.
   */
  onAddTask?: ((listId: string | null) => void) | undefined;
}

export default function KanbanView({ onSelectTask, onAddTask }: Props) {
  const controller = useKanbanController({ onSelectTask });
  const { locale } = useI18n();
  const scroll = useScrollRestore('kanban');
  const { runtimeClass } = useRuntimeProfile();
  const isMobile = runtimeClass === 'mobile';

  // Mobile the desktop horizontal-scroll column board is
  // unusable on phones (375px viewport crops columns, HTML5 DnD doesn't
  // fire on touch). Render a tab bar + vertical list instead; keep the
  // same header controls so the filter story is unchanged.
  const mobileHeaderPadding = isMobile ? 'px-4 pt-1.5 pb-3' : 'px-4 sm:px-8 pt-1.5 pb-5';

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

  return (
    <TaskListViewShell
      pageTitleKey="nav.kanban"
      containerClassName={`h-full flex flex-col ${isMobile ? 'overflow-hidden' : 'overflow-x-auto overflow-y-hidden'}`}
      headerClassName={`${mobileHeaderPadding} shrink-0`}
      headerContent={
        <>
          <p className="text-text-muted text-xs font-medium mb-1">{controller.t('kanban.title')}</p>
          <div className="flex items-baseline justify-between">
            <h2 className="text-text-primary text-2xl font-light">{controller.t('kanban.subtitle')}</h2>
            <div className="flex items-center gap-3">
              {/* ensure the chip clears the WCAG 2.5.5
                  24×24 minimum hit target (pre-fix it was ~16 px tall). */}
              {controller.allFlatTasks.length > 0 && (
                <button
                  type="button"
                  onClick={() => { void controller.handleCopyBoard(); }}
                  disabled={controller.copying}
                  className="text-text-muted text-xs hover:text-text-secondary active:scale-[0.97] transition-[color,opacity,transform] disabled:opacity-50 rounded-r-control focus-ring-soft px-2 py-1.5 min-h-8 inline-flex items-center"
                >
                  {controller.copying ? controller.t('common.copying') : controller.t('kanban.copyBoard')}
                </button>
              )}
              {onAddTask && (
                <AddTaskHeaderButton
                  labelKey="kanban.addTask"
                  tooltipKey="kanban.addTaskTooltip"
                  onClick={() => onAddTask(controller.filterListId)}
                />
              )}
            </div>
          </div>
        </>
      }
      toolbar={{
        search: searchSlot,
        searchSuffix: (
          <>
            <Toggle
              checked={controller.showCompleted}
              onChange={controller.setShowCompleted}
              label={controller.t('kanban.showCompleted')}
            />
            <span className="text-text-muted text-xs tabular-nums">
              {formatTaskCountLabel(locale, controller.totalCount, controller.t)}
            </span>
          </>
        ),
        filterList: filterListSlot,
        filterPriority: filterPrioritySlot,
        filterTag: filterTagSlot,
        extraFilters: (
          <>
            <TimeHorizonPicker value={controller.horizonDays} onChange={controller.setHorizonDays} />
            <SavedQueriesMenu
              viewType="Kanban"
              onCapture={() =>
                serializeViewFilters({
                  search: controller.search,
                  filterListId: controller.filterListId,
                  filterPriority: controller.filterPriority,
                  selectedTags: controller.selectedTags,
                  showCompleted: controller.showCompleted,
                  horizonDays: controller.horizonDays,
                })
              }
              onApply={(filterJson) => {
                const decoded = deserializeViewFilters(filterJson);
                controller.setSearch(decoded.search ?? '');
                controller.setFilterListId(decoded.listId ?? null);
                controller.setFilterPriority(decoded.priority ?? null);
                controller.replaceSelectedTags(decoded.tags ?? []);
                if (decoded.showCompleted !== undefined)
                  controller.setShowCompleted(decoded.showCompleted);
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
        isMobile ? (
          <KanbanMobileView controller={controller} onSelectTask={onSelectTask} />
        ) : (
          <div ref={scroll.ref} onScroll={scroll.onScroll} className="flex-1 overflow-x-auto overflow-y-hidden px-4 sm:px-8 pb-8">
            {/* surface non-blocking error when a background
                refetch fails but cached data is still visible. Previously
                this state was silent — user kept dragging stale rows with
                no idea the backend was unreachable. */}
            {controller.isError && controller.allFlatTasks.length > 0 && (
              <StaleDataBanner t={controller.t} onRetry={() => { void controller.refetch(); }} />
            )}
            <TaskBoardBodyState
              isLoading={controller.isLoading}
              isError={controller.isError}
              hasAnyData={controller.allFlatTasks.length > 0}
              isNoMatch={controller.filteredTasks.length === 0 && controller.isFilterActive && controller.totalTaskCount > 0}
              loading={<KanbanViewSkeleton />}
              onRetry={() => { void controller.refetch(); }}
              noMatch={{
                icon: <SearchIcon className="w-9 h-9" />,
                title: controller.t('allTasks.emptyNoMatch'),
                subtitle: controller.t('allTasks.emptySearchHint'),
              }}
            >
              <div className="flex gap-4 h-full min-w-0">
                {controller.visibleColumnKeys.map((key) => (
                  <Column
                    key={key}
                    columnKey={key}
                    title={controller.t(COLUMN_LABEL_KEYS[key])}
                    tasks={controller.columns[key]}
                    styleClass={COLUMN_STYLE[key]}
                    completed={key === 'completed'}
                    onSelectTask={onSelectTask}
                    isFocused={controller.keyboard.isFocused}
                    focusedTaskId={controller.keyboard.focusedId}
                    emptyLabel={controller.t('kanban.empty')}
                    dropHint={controller.t('kanban.dropHere')}
                    isDragOver={controller.dragOverColumn === key}
                    isBusy={controller.moveToColumnPending}
                    onDragOverColumn={controller.setDragOverColumn}
                    onDrop={controller.handleDrop}
                  />
                ))}
              </div>
            </TaskBoardBodyState>
          </div>
        )
      }
      pickerTasks={controller.allFlatTasks}
      pickerActions={controller.kbActions}
    />
  );
}
