import { memo, useCallback, type KeyboardEvent as ReactKeyboardEvent, type MouseEvent as ReactMouseEvent } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { ariaKeyShortcutsForModChord } from '@/lib/shortcuts';
import { InteractiveTaskCard } from '../task-card/InteractiveTaskCard';
import { addDays } from '../calendar/calendarViewUtils';
import { DRAG_MIME } from './useUpcomingController';

const UPCOMING_RESCHEDULE_ARIA_KEYSHORTCUTS = [
  ariaKeyShortcutsForModChord(['Mod', 'Shift', 'ArrowLeft']),
  ariaKeyShortcutsForModChord(['Mod', 'Shift', 'ArrowRight']),
  ariaKeyShortcutsForModChord(['Mod', 'Shift', 'ArrowDown']),
].join(' ');

interface UpcomingTaskRowProps {
  task: Task;
  selectionMode: boolean;
  selected: boolean;
  bulkBusy: boolean;
  focused: boolean;
  hasSelection: boolean;
  onToggleSelected: (id: string) => void;
  onSelect?: ((id: string) => void) | undefined;
  onClickWithModifiers: (id: string, event: ReactMouseEvent<HTMLButtonElement>) => void;
  /**
   * Keyboard reschedule: when present, Cmd/Ctrl+Shift+Arrow
   * shifts the focused task by ±1 day (←/→) or +7 days (↓). The row
   * delegates to the parent's existing reschedule mutation so cache
   * invalidation + toast logic stay in one place.
   */
  onRescheduleTask?: (taskId: string, newDate: string) => void;
  onDragEnd?: () => void;
}

function UpcomingTaskRowImpl({
  task,
  selectionMode,
  selected,
  bulkBusy,
  focused,
  hasSelection,
  onToggleSelected,
  onSelect,
  onClickWithModifiers,
  onRescheduleTask,
  onDragEnd,
}: UpcomingTaskRowProps) {
  // Cmd+Shift+Arrow keyboard reschedule. Mirrors MonthGrid pills'
  // `useKeyboardReschedule` semantics but layered behind the
  // Cmd/Ctrl+Shift modifier so plain Arrow keys keep their meaning
  // for the task-list-keyboard contract (j/k navigation, Enter to
  // open). We resolve the canonical "effective" date the same way
  // `handleRescheduleTask` in the controller does: prefer
  // planned_date, else due_date. Tasks with no schedule yet skip.
  const handleKeyDown = useCallback((event: ReactKeyboardEvent<HTMLDivElement>) => {
    if (!onRescheduleTask) return;
    if (!event.shiftKey) return;
    if (!(event.metaKey || event.ctrlKey)) return;
    if (event.altKey) return;
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight' && event.key !== 'ArrowDown') return;
    const anchor = task.planned_date ?? task.due_date;
    if (!anchor) return;
    event.preventDefault();
    event.stopPropagation();
    const delta = event.key === 'ArrowLeft' ? -1 : event.key === 'ArrowRight' ? 1 : 7;
    onRescheduleTask(task.id, addDays(anchor, delta));
  }, [onRescheduleTask, task.due_date, task.id, task.planned_date]);

  if (selectionMode) {
    return (
      <InteractiveTaskCard
        task={task}
        selectionMode
        selected={selected}
        bulkBusy={bulkBusy}
        onToggleSelected={onToggleSelected}
      />
    );
  }

  return (
    <div
      draggable
      role="group"
      onDragStart={(event) => {
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData(DRAG_MIME, task.id);
      }}
      onDragEnd={onDragEnd}
      onKeyDown={handleKeyDown}
      // SR users get the keyboard contract — list keyboard hint bar
      // covers the global j/k/Enter set; this one is row-local so
      // keep it on the row wrapper itself. The actual interactive
      // surface (the task button + checkbox) lives inside
      // `InteractiveTaskCard`; this wrapper exists only to host the
      // drag-source contract and the row-local key shortcut, hence
      // the static-element disable.
      aria-keyshortcuts={onRescheduleTask ? UPCOMING_RESCHEDULE_ARIA_KEYSHORTCUTS : undefined}
      className="cursor-grab active:cursor-grabbing"
    >
      <InteractiveTaskCard
        task={task}
        selectionMode={false}
        selected={selected}
        focused={focused}
        hasSelection={hasSelection}
        onSelect={onSelect}
        onClickWithModifiers={onClickWithModifiers}
      />
    </div>
  );
}

// Memoize so `dragOverDate` state ticks in the parent don't re-render
// every row in every date section. The default shallow prop compare is
// sufficient once the parent holds stable handler references.
export const UpcomingTaskRow = memo(UpcomingTaskRowImpl);
