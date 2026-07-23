import { memo, useCallback } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { applyCompactDragImage } from '@/lib/dragImage';
import { ariaKeyShortcutsForModChord } from '@/lib/shortcuts';
import TaskCard from '../task-card/TaskCard';
import { SwipeableTaskCard } from '../task-card/SwipeableTaskCard';
import { DRAG_MIME, type QuadrantKey } from './quadrants';

const EISENHOWER_TASK_MOVE_ARIA_KEY_SHORTCUTS = [
  ariaKeyShortcutsForModChord(['Mod', 'ArrowLeft']),
  ariaKeyShortcutsForModChord(['Mod', 'ArrowRight']),
  ariaKeyShortcutsForModChord(['Mod', 'ArrowUp']),
  ariaKeyShortcutsForModChord(['Mod', 'ArrowDown']),
].join(' ');

/**
 * Memoized Eisenhower row — same rationale as `KanbanTaskRow` (audit
 * ). Inline per-task `onDragStart` / `onDragEnd` / `onClick`
 * closures in the parent `.map` defeated `TaskCard`'s memo comparator;
 * extracting the row lets each instance hold its own stable
 * `useCallback` handlers so a `dragOverQuadrant` state tick doesn't
 * re-render every card across all four quadrants.
 */
export const EisenhowerTaskRow = memo(function EisenhowerTaskRow({
  task,
  isBusy,
  focused,
  justDropped,
  onDragOverQuadrant,
  onSelectTask,
}: {
  task: Task;
  isBusy: boolean;
  focused: boolean;
  justDropped: boolean;
  onDragOverQuadrant: (quadrant: QuadrantKey | null) => void;
  onSelectTask?: ((taskId: string) => void) | undefined;
}) {
  const handleDragStart = useCallback(
    (event: React.DragEvent<HTMLDivElement>) => {
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData(DRAG_MIME, task.id);
      applyCompactDragImage(event, { title: task.title, icon: '✦' });
    },
    [task.id, task.title],
  );
  const handleDragEnd = useCallback(() => onDragOverQuadrant(null), [onDragOverQuadrant]);
  const handleClick = useCallback(() => onSelectTask?.(task.id), [onSelectTask, task.id]);

  // Expose the keyboard alternative to drag-drop.
  // The view's controller binds Ctrl/Cmd+Arrow (all four directions)
  // to `onMoveInView`, which routes to the focused row:
  //   - Ctrl/Cmd+ArrowLeft  → make important
  //   - Ctrl/Cmd+ArrowRight → make non-important
  // - Ctrl/Cmd+ArrowUp    → make urgent (due today,)
  // - Ctrl/Cmd+ArrowDown  → make non-urgent (clear due date,)
  return (
    // HTML5 draggable wrapper. The actionable target is the inner
    // <TaskCard> button; this <div> only forwards drag events.
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <div
      draggable={!isBusy}
      onDragStart={handleDragStart}
      onDragEnd={handleDragEnd}
      className={`cursor-grab active:cursor-grabbing ${justDropped ? 'drop-settle' : ''}`}
    >
      <SwipeableTaskCard task={task}>
        <TaskCard
          task={task}
          focused={focused}
          onClick={handleClick}
          taskButtonAriaRoleDescription="draggable"
          taskButtonAriaKeyShortcuts={EISENHOWER_TASK_MOVE_ARIA_KEY_SHORTCUTS}
        />
      </SwipeableTaskCard>
    </div>
  );
});
