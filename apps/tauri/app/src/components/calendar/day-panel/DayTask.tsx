import { memo } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { useI18n } from '@/lib/i18n';
import { applyCompactDragImage } from '@/lib/dragImage';
import { CheckIcon } from '@/components/ui/icons';
import { formatDurationCompact } from '@/components/today-view/primitives';
import { CALENDAR_TASK_DRAG_MIME, RECURRENCE_SYMBOL, encodeCalendarTaskDrag } from '../calendarViewUtils';

// wrapped in `memo` so a drag-over hover or sibling row mount
// in `DayPanel` doesn't re-render every task row. Parent must pass
// stable handlers (see DayPanel `useCallback` hoists) for the memo to
// actually skip re-renders.
function DayTaskInner({
  task,
  onOpen,
  onComplete,
  onReopen,
  completeLabelPrefix,
  done = false,
  openButtonRef,
}: {
  task: Task;
  onOpen: (id: string) => void;
  onComplete: (task: Task) => void;
  onReopen?: (task: Task) => void;
  completeLabelPrefix: string;
  done?: boolean;
  /**
   * Ref callback for the "open task" button. DayPanel's
   * roving j/k focus targets this button so Enter on the focused
   * row opens the task detail. Optional so non-keyboard call sites
   * stay unaffected.
   */
  openButtonRef?: ((node: HTMLElement | null) => void) | undefined;
}) {
  const { t, formatNumber } = useI18n();
  const hasDueTime = typeof task.due_time === 'string' && task.due_time.trim().length > 0;

  return (
    // HTML5 draggable wrapper. The actionable targets are the inner
    // complete + open buttons; this <div> only forwards drag events.
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <div
      draggable={!done}
      onDragStart={(event) => {
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData(CALENDAR_TASK_DRAG_MIME, encodeCalendarTaskDrag(task.id, task.planned_date ?? task.due_date, !!task.planned_date, task.due_time));
        applyCompactDragImage(event, { title: task.title, icon: '✦' });
      }}
      className={`flex items-start gap-2 px-3 py-2 rounded-r-control transition-colors hover:bg-surface-2 group ${done ? 'opacity-50' : 'cursor-grab active:cursor-grabbing'}`}
    >
      {(hasDueTime || task.estimated_minutes) ? (
        <span className="shrink-0 w-fit min-w-10 text-xs text-text-muted font-mono pt-0.5 text-end">
          {hasDueTime ? task.due_time : ''}
          {hasDueTime && task.estimated_minutes ? ' · ' : ''}
          {task.estimated_minutes ? formatDurationCompact(task.estimated_minutes, t('common.hourShort'), t('common.min'), formatNumber) : ''}
        </span>
      ) : null}
      <button
        type="button"
        onClick={(event_) => {
          event_.stopPropagation();
          if (done) {
            onReopen?.(task);
          } else {
            onComplete(task);
          }
        }}
        className={`shrink-0 mt-0.5 w-4 h-4 rounded-full border transition-colors ${
          done
            ? 'bg-success border-success flex items-center justify-center hover:bg-[var(--success-tint-2xl)] focus-ring-soft'
            : 'border-surface-3 group-hover:border-text-muted/50 hover:border-success hover:bg-[var(--success-tint-sm)] focus-ring-soft'
        }`}
        aria-label={`${completeLabelPrefix}: ${task.title}`}
      >
        {done ? <CheckIcon className="w-2.5 h-2.5 text-white" /> : null}
      </button>
      <button
        ref={openButtonRef}
        type="button"
        onClick={() => onOpen(task.id)}
        aria-label={task.title}
        className={`flex-1 min-w-0 wrap-break-word text-start text-xs leading-snug rounded-r-control ${done ? 'line-through text-text-muted' : 'text-text-secondary hover:text-text-primary'} focus-ring-soft`}
      >
        {task.recurrence ? RECURRENCE_SYMBOL : ''}{task.title}
      </button>
    </div>
  );
}

export const DayTask = memo(DayTaskInner);
