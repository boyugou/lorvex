import { memo, useCallback, useMemo, useRef, useState } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { useI18n } from '@/lib/i18n';
import { useScrollRestore } from '@/lib/useScrollRestore';
import TaskCard from '../task-card/TaskCard';
import { SwipeableTaskCard } from '../task-card/SwipeableTaskCard';
import { ContextMenu, type ContextMenuItem } from '../context-menu/ContextMenu';
import { ArrowRightIcon, MoveIcon, SearchIcon, WarningIcon } from '../ui/icons';
import ModuleStatePanel from '../ui/ModuleStatePanel';
import { StaleDataBanner } from '../ui/StaleDataBanner';
import { formatDurationCompact } from '../today-view/primitives';
import {
  COLUMN_LABEL_KEYS,
  COLUMN_MOVE_LABEL_KEYS,
  type ColumnKey,
} from './columns';
import type { KanbanController } from './useKanbanController';

interface Props {
  controller: KanbanController;
  onSelectTask?: ((taskId: string) => void) | undefined;
}

/**
 * Mobile Kanban layout: the desktop horizontal-scroll
 * board cropped columns at 375px and relied on HTML5 drag-and-drop —
 * which doesn't fire on touch. We instead show a tab bar of columns +
 * a full-width vertical task list for the active tab. Moving between
 * columns happens via an explicit "Move" button on each row (opens a
 * small popover menu), which is far more discoverable than any
 * long-press touch-drag polyfill.
 */
export default function KanbanMobileView({ controller, onSelectTask }: Props) {
  const { formatNumber } = useI18n();
  const { t } = controller;
  const scroll = useScrollRestore('kanban-mobile');

  const [activeColumn, setActiveColumn] = useState<ColumnKey>(() => {
    const initial = controller.visibleColumnKeys[0];
    return (initial ?? 'open') as ColumnKey;
  });

  // If the user toggles `Show completed` off while the Completed tab is
  // active, snap back to the first visible column instead of rendering
  // an empty/orphaned tab.
  const activeColumnIsVisible = controller.visibleColumnKeys.includes(activeColumn);
  const effectiveActiveColumn: ColumnKey = activeColumnIsVisible
    ? activeColumn
    : ((controller.visibleColumnKeys[0] ?? 'open') as ColumnKey);

  const activeTasks = controller.columns[effectiveActiveColumn];

  // a11y: WAI-ARIA tabs use roving tabIndex (only the active tab is
  // in the Tab order, the others are reachable via
  // ArrowLeft/ArrowRight while focus is in the tablist) plus a
  // `tabpanel` body owned by the active tab via `aria-controls`, so
  // a keyboard user reaches the task list in one Tab instead of
  // tabbing through every column. Refs let the arrow-key handler
  // move focus to the next/previous tab DOM node (focus follows
  // selection).
  const tabRefs = useRef<Record<string, HTMLButtonElement | null>>({});
  const visibleKeys = controller.visibleColumnKeys;
  const handleTabKeyDown = useCallback(
    (event: React.KeyboardEvent, currentKey: ColumnKey) => {
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight'
        && event.key !== 'Home' && event.key !== 'End') return;
      event.preventDefault();
      const idx = visibleKeys.indexOf(currentKey);
      if (idx < 0) return;
      let nextIdx = idx;
      if (event.key === 'ArrowLeft') nextIdx = (idx - 1 + visibleKeys.length) % visibleKeys.length;
      else if (event.key === 'ArrowRight') nextIdx = (idx + 1) % visibleKeys.length;
      else if (event.key === 'Home') nextIdx = 0;
      else if (event.key === 'End') nextIdx = visibleKeys.length - 1;
      const nextKey = visibleKeys[nextIdx];
      if (!nextKey) return;
      setActiveColumn(nextKey as ColumnKey);
      tabRefs.current[nextKey]?.focus();
    },
    [visibleKeys],
  );

  return (
    <>
      {/* Tab bar */}
      <div className="px-4 shrink-0 border-b border-surface-3">
        <div role="tablist" aria-label={t('kanban.mobile.selectColumn')} className="flex gap-1">
          {visibleKeys.map((key) => {
            const isActive = key === effectiveActiveColumn;
            const count = controller.columns[key].length;
            return (
              <button
                key={key}
                ref={(node) => { tabRefs.current[key] = node; }}
                type="button"
                role="tab"
                id={`kanban-mobile-tab-${key}`}
                aria-selected={isActive}
                aria-controls={`kanban-mobile-tabpanel-${key}`}
                tabIndex={isActive ? 0 : -1}
                onClick={() => setActiveColumn(key as ColumnKey)}
                onKeyDown={(event) => handleTabKeyDown(event, key as ColumnKey)}
                className={`flex-1 min-h-11 px-3 pt-3 pb-2.5 text-sm font-medium tabular-nums transition-colors border-b-2 ${
                  isActive
                    ? 'text-text-primary border-accent'
                    : 'text-text-muted border-transparent active:text-text-secondary'
                }`}
              >
                <span>{t(COLUMN_LABEL_KEYS[key])}</span>
                <span className="ms-1.5 text-xs text-text-muted">{formatNumber(count)}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Active column body */}
      {/* The WAI-ARIA Authoring Practices Guide recommends tabIndex={0}
          on a tabpanel so keyboard users can scroll its overflow with
          arrow keys. jsx-a11y reads the role generically and treats it
          as non-interactive; the override is intentional. */}
      <div
        ref={scroll.ref}
        onScroll={scroll.onScroll}
        role="tabpanel"
        id={`kanban-mobile-tabpanel-${effectiveActiveColumn}`}
        aria-labelledby={`kanban-mobile-tab-${effectiveActiveColumn}`}
        // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
        tabIndex={0}
        className="flex-1 overflow-y-auto overflow-x-hidden px-4 pt-3 pb-8"
      >
        {controller.isError && controller.allFlatTasks.length > 0 && (
          <StaleDataBanner t={t} onRetry={() => { void controller.refetch(); }} />
        )}
        {controller.isLoading ? (
          <ModuleStatePanel variant="loading" />
        ) : controller.isError && controller.allFlatTasks.length === 0 ? (
          <ModuleStatePanel
            variant="error"
            icon={<WarningIcon className="w-9 h-9" />}
            title={t('common.loadFailed')}
            subtitle={t('common.loadFailedHint')}
            actionLabel={t('error.tryAgain')}
            onAction={() => { void controller.refetch(); }}
          />
        ) : controller.filteredTasks.length === 0 && controller.isFilterActive && controller.totalTaskCount > 0 ? (
          <ModuleStatePanel
            icon={<SearchIcon className="w-9 h-9" />}
            title={t('allTasks.emptyNoMatch')}
            subtitle={t('allTasks.emptySearchHint')}
          />
        ) : (
          <KanbanMobileTaskList
            columnKey={effectiveActiveColumn}
            tasks={activeTasks}
            onMoveToColumn={controller.handleDrop}
            isBusy={controller.moveToColumnPending}
            onSelectTask={onSelectTask}
            isFocused={controller.keyboard.isFocused}
          />
        )}
      </div>
    </>
  );
}

// ---------------------------------------------------------------------------
// Vertical task list for the active column
// ---------------------------------------------------------------------------

function KanbanMobileTaskList({
  columnKey,
  tasks,
  onMoveToColumn,
  isBusy,
  onSelectTask,
  isFocused,
}: {
  columnKey: ColumnKey;
  tasks: Task[];
  onMoveToColumn: (target: ColumnKey, taskId: string) => void;
  isBusy: boolean;
  onSelectTask?: ((taskId: string) => void) | undefined;
  isFocused: (taskId: string) => boolean;
}) {
  const { t, formatNumber } = useI18n();
  const totalMin = tasks.reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0);

  if (tasks.length === 0) {
    return (
      <div className="rounded-r-card border border-dashed border-surface-3 min-h-[200px] flex items-center justify-center">
        <p className="text-text-muted text-sm">{t('kanban.empty')}</p>
      </div>
    );
  }

  return (
    <>
      {totalMin > 0 && (
        <div className="mb-2 text-text-muted text-xs tabular-nums">
          {formatDurationCompact(totalMin, t('common.hourShort'), t('common.min'), formatNumber)}
        </div>
      )}
      <div className="space-y-2">
        {tasks.map((task) => (
          <KanbanMobileTaskRow
            key={task.id}
            task={task}
            sourceColumn={columnKey}
            isBusy={isBusy}
            completed={columnKey === 'completed'}
            focused={isFocused(task.id)}
            onMoveToColumn={onMoveToColumn}
            onSelectTask={onSelectTask}
          />
        ))}
      </div>
    </>
  );
}

// ---------------------------------------------------------------------------
// Row = swipeable TaskCard + explicit "Move" button (opens popover menu of
// destination columns). No `draggable` attribute — HTML5 DnD is a no-op on
// touch and its presence confuses assistive tech.
// ---------------------------------------------------------------------------

const KanbanMobileTaskRow = memo(function KanbanMobileTaskRow({
  task,
  sourceColumn,
  isBusy,
  completed,
  focused,
  onMoveToColumn,
  onSelectTask,
}: {
  task: Task;
  sourceColumn: ColumnKey;
  isBusy: boolean;
  completed: boolean;
  focused: boolean;
  onMoveToColumn: (target: ColumnKey, taskId: string) => void;
  onSelectTask?: ((taskId: string) => void) | undefined;
}) {
  const { t } = useI18n();
  const [menuState, setMenuState] = useState<{
    position: { x: number; y: number };
    triggerElement: HTMLElement | null;
  } | null>(null);

  const handleClick = useCallback(() => onSelectTask?.(task.id), [onSelectTask, task.id]);

  const moveItems = useMemo<ContextMenuItem[]>(() => {
    // Offer every other column as a move target. This deliberately
    // shadows the generic TaskCard long-press menu for the one
    // Kanban-specific action (column move) that the generic menu
    // doesn't expose.
    const targets: ColumnKey[] = (['open', 'someday', 'completed'] as ColumnKey[]).filter(
      (key) => key !== sourceColumn,
    );
    return targets.map<ContextMenuItem>((target) => ({
      key: `move-${target}`,
      label: t(COLUMN_MOVE_LABEL_KEYS[target]),
      icon: <ArrowRightIcon className="w-3.5 h-3.5" />,
      disabled: isBusy,
      onSelect: () => onMoveToColumn(target, task.id),
    }));
  }, [isBusy, onMoveToColumn, sourceColumn, t, task.id]);

  const openMoveMenu = useCallback((event: React.MouseEvent<HTMLButtonElement>) => {
    event.preventDefault();
    event.stopPropagation();
    const rect = event.currentTarget.getBoundingClientRect();
    setMenuState({
      position: { x: rect.right, y: rect.bottom },
      triggerElement: event.currentTarget,
    });
  }, []);

  const closeMenu = useCallback(() => setMenuState(null), []);

  return (
    <div data-kanban-mobile-task-row="true" className="flex items-center gap-2">
      <div className="min-w-0 flex-1">
        <SwipeableTaskCard task={task}>
          <TaskCard
            task={task}
            completed={completed}
            focused={focused}
            onClick={handleClick}
          />
        </SwipeableTaskCard>
      </div>

      {/* Move button — always visible on mobile (no hover affordance).
          Keep it in normal row flow so the touch-visible TaskCard quick
          actions never sit underneath this adjacent 44px control. */}
      <button
        type="button"
        onClick={openMoveMenu}
        disabled={isBusy}
        aria-label={t('kanban.mobile.moveTo')}
        title={t('kanban.mobile.moveTo')}
        className="shrink-0 min-h-11 min-w-11 flex items-center justify-center rounded-r-card text-text-muted bg-surface-2 border border-transparent active:bg-surface-3 active:text-text-primary disabled:opacity-40 disabled:pointer-events-none focus-ring-soft"
      >
        <MoveIcon className="w-4 h-4" />
      </button>

      {menuState && (
        <ContextMenu
          items={moveItems}
          position={menuState.position}
          onClose={closeMenu}
          triggerElement={menuState.triggerElement}
        />
      )}
    </div>
  );
});
