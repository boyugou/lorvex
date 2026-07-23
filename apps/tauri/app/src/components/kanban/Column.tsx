import { memo, useCallback, useMemo, useRef, useState } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { isSpuriousDragLeave } from '../../lib/dragLeave';
import { applyCompactDragImage } from '@/lib/dragImage';
import { ariaKeyShortcutsForModChord } from '@/lib/shortcuts';
import TaskCard from '../task-card/TaskCard';
import { SwipeableTaskCard } from '../task-card/SwipeableTaskCard';
import {
  shouldVirtualizeListView,
  useVirtualizedTaskColumn,
} from '../list-view/virtualization';
import { ColumnHeader } from './ColumnHeader';
import { DRAG_MIME, type ColumnKey } from './columns';

const KANBAN_TASK_MOVE_ARIA_KEY_SHORTCUTS = [
  ariaKeyShortcutsForModChord(['Mod', 'ArrowLeft']),
  ariaKeyShortcutsForModChord(['Mod', 'ArrowRight']),
].join(' ');

/**
 * One Kanban column with header, drag-drop target, and per-row card
 * list (virtualized when over the row threshold). Memoized so a
 * `dragOverColumn` state tick on the parent re-renders only the
 * column whose `isDragOver` flipped, not every column on the board.
 *
 * Callers MUST pass stable callbacks for `onDragOverColumn` and
 * `onDrop` (e.g. via `useCallback`); fresh closures defeat memo.
 */
interface ColumnProps {
  columnKey: ColumnKey;
  title: string;
  tasks: Task[];
  styleClass: string;
  completed: boolean;
  onSelectTask?: ((taskId: string) => void) | undefined;
  isFocused: (taskId: string) => boolean;
  focusedTaskId: string | null;
  emptyLabel: string;
  dropHint: string;
  isDragOver: boolean;
  isBusy: boolean;
  onDragOverColumn: (column: ColumnKey | null) => void;
  onDrop: (column: ColumnKey, taskId: string) => void;
}

export const Column = memo(function Column({
  columnKey,
  title,
  tasks,
  styleClass,
  completed,
  onSelectTask,
  isFocused,
  focusedTaskId,
  emptyLabel,
  dropHint,
  isDragOver,
  isBusy,
  onDragOverColumn,
  onDrop,
}: ColumnProps) {
  // Pre-memoize per-section task aggregates — `useMemo` here means a
  // parent state tick that re-renders the board but leaves this
  // column's `tasks` reference unchanged skips the sum entirely.
  const totalMin = useMemo(
    () => tasks.reduce((sum, tk) => sum + (tk.estimated_minutes ?? 0), 0),
    [tasks],
  );

  // In-column drop placeholder index. `null` means "no preview row";
  // a number means "render a placeholder between rows[i-1] and
  // rows[i]" (so `tasks.length` is the special "after the last row"
  // case). We compute it from the cursor Y on each `onDragOver` —
  // see `computeDropIndex` for the row-midpoint heuristic. We
  // intentionally keep this co-located with the column rather than
  // hoisted to the parent so a board-level state tick on
  // `dragOverColumn` doesn't churn the whole board, and so the
  // placeholder index resets cleanly on dragLeave.
  const [dropIndex, setDropIndex] = useState<number | null>(null);
  // Track the in-flight drag-source taskId so its row dims to ~30%
  // while the user is dragging — telegraphs "this is the moving
  // card" visually so the user isn't looking at two identical
  // rows. Cleared on dragEnd / drop. Local to the column so a
  // sibling column's hover-tick doesn't churn this one.
  const [draggingTaskId, setDraggingTaskId] = useState<string | null>(null);
  const rowsContainerRef = useRef<HTMLDivElement>(null);

  return (
    <section
      aria-label={title}
      // Standardize drag-over feedback to match Eisenhower /
      // Upcoming — `ring-2 ring-accent/50 bg-accent/5`, no parent
      // scale (it shifted neighboring columns and added jitter).
      className={`rounded-r-card border p-3 min-w-[160px] md:min-w-[220px] min-h-[300px] flex-1 flex flex-col transition-[box-shadow,background-color] ${styleClass} ${
        isDragOver ? 'ring-2 ring-accent/50 bg-accent/5' : ''
      }`}
      onDragOver={(event) => {
        if (isBusy) return;
        if (!event.dataTransfer.types.includes(DRAG_MIME)) return;
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        onDragOverColumn(columnKey);
        const next = computeDropIndex(rowsContainerRef.current, event.clientY, tasks.length);
        setDropIndex((prev) => (prev === next ? prev : next));
      }}
      onDragLeave={(event) => {
        // shared spurious-leave guard kills the flicker
        // when the cursor crosses into an inner pill / Tooltip portal
        // whose relatedTarget is reported as `null` by the browser.
        if (isSpuriousDragLeave(event)) return;
        onDragOverColumn(null);
        setDropIndex(null);
      }}
      onDrop={(event) => {
        event.preventDefault();
        setDropIndex(null);
        const taskId = event.dataTransfer.getData(DRAG_MIME);
        if (taskId) onDrop(columnKey, taskId);
      }}
    >
      <ColumnHeader title={title} totalMinutes={totalMin} count={tasks.length} />

      {tasks.length === 0 ? (
        <div className={`flex-1 min-h-[200px] rounded-r-card border border-dashed flex items-center justify-center ${
          isDragOver ? 'border-accent/50 bg-accent/10' : 'border-surface-3'
        }`}>
          <p className="text-text-muted text-xs">{isDragOver ? dropHint : emptyLabel}</p>
        </div>
      ) : shouldVirtualizeListView(tasks.length) ? (
        <VirtualizedColumn
          tasks={tasks}
          isBusy={isBusy}
          completed={completed}
          isFocused={isFocused}
          focusedTaskId={focusedTaskId}
          onDragOverColumn={onDragOverColumn}
          onSelectTask={onSelectTask}
          draggingTaskId={draggingTaskId}
          setDraggingTaskId={setDraggingTaskId}
        />
      ) : (
        <div
          ref={rowsContainerRef}
          className="flex-1 overflow-y-auto overscroll-contain space-y-1.5"
          data-kanban-rows
        >
          {tasks.map((task, index) => (
            <div key={task.id} data-kanban-row>
              {/* Placeholder line slides in between rows when the
                  cursor crosses a row midpoint. Showing it as a
                  thin accent-tinted bar (rather than a full-height
                  ghost card) keeps the column layout from jumping
                  while still telegraphing the precise insertion
                  point. */}
              {isDragOver && dropIndex === index && (
                <KanbanDropPlaceholder />
              )}
              <KanbanTaskRow
                task={task}
                isBusy={isBusy}
                completed={completed}
                focused={isFocused(task.id)}
                onDragOverColumn={onDragOverColumn}
                onSelectTask={onSelectTask}
                dragging={draggingTaskId === task.id}
                setDraggingTaskId={setDraggingTaskId}
              />
            </div>
          ))}
          {isDragOver && dropIndex === tasks.length && (
            <KanbanDropPlaceholder />
          )}
        </div>
      )}
    </section>
  );
});

/**
 * Compute the insertion index for an in-column drop given the
 * cursor's clientY and the row-container DOM node. We walk each
 * `[data-kanban-row]` child, find the first one whose midpoint sits
 * below the cursor, and return that child's index. If the cursor is
 * past every row's midpoint, we return `tasks.length` ("drop at the
 * end"). When the container is missing (initial mount, virtualized
 * path, etc.), we fall back to `taskCount` so the placeholder lands
 * at the end rather than guessing wrong.
 *
 * Pure DOM math — no React state — so it's safe to call inside
 * `onDragOver` without queueing a render per pixel.
 */
function computeDropIndex(
  container: HTMLDivElement | null,
  clientY: number,
  taskCount: number,
): number {
  if (!container) return taskCount;
  const rows = container.querySelectorAll<HTMLElement>('[data-kanban-row]');
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (!row) continue;
    const rect = row.getBoundingClientRect();
    const midpoint = rect.top + rect.height / 2;
    if (clientY < midpoint) return i;
  }
  return taskCount;
}

function KanbanDropPlaceholder() {
  return (
    <div
      aria-hidden="true"
      className="my-0.5 h-1 rounded-r-control bg-accent/55 shadow-[0_0_0_1px_var(--accent-tint-md)] transition-opacity"
    />
  );
}

/**
 * Virtualized per-column rail for large Kanban columns. Matches
 * the `ListView` pattern: own the scroll element locally, window rows
 * through `@tanstack/react-virtual`, and call `scrollToIndex` on focus
 * changes so keyboard navigation (j/k) keeps the focused card in view
 * even when the task id is outside the currently-mounted window.
 */
function VirtualizedColumn({
  tasks,
  isBusy,
  completed,
  isFocused,
  focusedTaskId,
  onDragOverColumn,
  onSelectTask,
  draggingTaskId,
  setDraggingTaskId,
}: {
  tasks: Task[];
  isBusy: boolean;
  completed: boolean;
  isFocused: (taskId: string) => boolean;
  focusedTaskId: string | null;
  onDragOverColumn: (column: ColumnKey | null) => void;
  onSelectTask?: ((taskId: string) => void) | undefined;
  draggingTaskId: string | null;
  setDraggingTaskId: (id: string | null) => void;
}) {
  // Virtualizer setup + scroll-to-focused effect lift to the shared
  // `useVirtualizedTaskColumn` hook so any tuning stays applied to
  // both this and `VirtualizedQuadrantList` in lockstep.
  const { scrollRef, virtualItems, totalSize, measureElement } =
    useVirtualizedTaskColumn(tasks, focusedTaskId);

  return (
    <div ref={scrollRef} className="flex-1 overflow-y-auto overscroll-contain">
      <div className="relative w-full" style={{ height: `${totalSize}px` }}>
        {virtualItems.map((vItem) => {
          const task = tasks[vItem.index];
          if (!task) return null;
          return (
            <div
              key={vItem.key}
              data-index={vItem.index}
              ref={measureElement}
              style={{
                position: 'absolute',
                top: 0,
                left: 0,
                width: '100%',
                transform: `translateY(${vItem.start}px)`,
              }}
            >
              <div className="py-0.5">
                <KanbanTaskRow
                  task={task}
                  isBusy={isBusy}
                  completed={completed}
                  focused={isFocused(task.id)}
                  onDragOverColumn={onDragOverColumn}
                  onSelectTask={onSelectTask}
                  dragging={draggingTaskId === task.id}
                  setDraggingTaskId={setDraggingTaskId}
                />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/**
 * Single Kanban row, memoized so a `dragOverColumn` state tick in the
 * parent doesn't re-render every card in every column. Inline
 * `onClick={() => onSelectTask?.(task.id)}` closures in the parent map
 * (perf audit) defeated `TaskCard`'s custom memo comparator;
 * encapsulating the per-task closure here keeps the TaskCard memo
 * boundary effective since the parent's `onSelectTask` reference is
 * stable across renders.
 */
const KanbanTaskRow = memo(function KanbanTaskRow({
  task,
  isBusy,
  completed,
  focused,
  onDragOverColumn,
  onSelectTask,
  dragging,
  setDraggingTaskId,
}: {
  task: Task;
  isBusy: boolean;
  completed: boolean;
  focused: boolean;
  onDragOverColumn: (column: ColumnKey | null) => void;
  onSelectTask?: ((taskId: string) => void) | undefined;
  dragging: boolean;
  setDraggingTaskId: (id: string | null) => void;
}) {
  const handleDragStart = useCallback(
    (event: React.DragEvent<HTMLDivElement>) => {
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData(DRAG_MIME, task.id);
      applyCompactDragImage(event, { title: task.title, icon: '✦' });
      setDraggingTaskId(task.id);
    },
    [task.id, task.title, setDraggingTaskId],
  );
  const handleDragEnd = useCallback(() => {
    setDraggingTaskId(null);
    onDragOverColumn(null);
  }, [onDragOverColumn, setDraggingTaskId]);
  const handleClick = useCallback(
    () => onSelectTask?.(task.id),
    [onSelectTask, task.id],
  );

  // Expose the keyboard alternative to drag-drop.
  // The controller wires Ctrl/Cmd+ArrowLeft/Right to
  // `onMoveInView`, which advances the focused task between
  // columns. Annotate the focusable task button so AT consumers hear
  // the drag-and-drop role plus the keyboard chord that replaces
  // the mouse drag.
  return (
    // HTML5 draggable wrapper. The actionable target is the inner
    // <TaskCard> button; this <div> only forwards drag events.
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <div
      draggable={!isBusy}
      onDragStart={handleDragStart}
      onDragEnd={handleDragEnd}
      className={`cursor-grab active:cursor-grabbing transition-opacity duration-150 ${dragging ? 'opacity-30' : ''}`}
    >
      <SwipeableTaskCard task={task}>
        <TaskCard
          task={task}
          completed={completed}
          focused={focused}
          onClick={handleClick}
          taskButtonAriaRoleDescription="draggable"
          taskButtonAriaKeyShortcuts={KANBAN_TASK_MOVE_ARIA_KEY_SHORTCUTS}
        />
      </SwipeableTaskCard>
    </div>
  );
});
