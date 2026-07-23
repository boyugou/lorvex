import { memo } from 'react';
import { WarningIcon } from '@/components/ui/icons';
import { applyCompactDragImage } from '@/lib/dragImage';
import { eventColorStyles } from '@/lib/colorUtils';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import { useI18n, type TranslationKey } from '@/lib/i18n';

import { eventTypeIcon } from '../eventTypeIcon';
import {
  CALENDAR_TASK_DRAG_MIME,
  RECURRENCE_SYMBOL,
  encodeCalendarTaskDrag,
} from '../calendarViewUtils';
import { formatCalendarEventAccessibleLabel } from '../calendarEventAccessibility';
import { useKeyboardReschedule } from '../useKeyboardReschedule';

/* ------------------------------------------------------------------ */
/* Desktop pill subcomponents.                                         */
/*                                                                     */
/* Extracted from the cell renderer so each pill can wire its own      */
/* `useKeyboardReschedule` hook, carry a screen-reader label, and      */
/* participate in normal Tab focus order without repeating all of that */
/* logic inline for every task / event.                                */
/* ------------------------------------------------------------------ */

interface DesktopTaskPillProps {
  task: Task;
  /// the cell's date_str so the pill can call back
  /// `onSelectDate(dateStr)` itself — the parent no longer needs to
  /// allocate a fresh arrow per pill per render, which was defeating
  /// the React.memo on this component (and its sibling DesktopEventPill).
  /// Same shape as the WeekTask onTaskFocus / onArrowNav contract.
  dateStr: string;
  dateLabel: string;
  isOverdue: boolean;
  t: (key: TranslationKey) => string;
  format: ReturnType<typeof useI18n>['format'];
  onSelectTask: ((taskId: string) => void) | undefined;
  onSelectDate: (dateStr: string) => void;
  onRescheduleTask:
    | ((taskId: string, newDate: string, oldDate: string | null, hasPlannedDate?: boolean) => void)
    | undefined;
  onDragEnd: () => void;
}

export const DesktopTaskPill = memo(function DesktopTaskPillImpl({
  task,
  dateStr,
  dateLabel,
  isOverdue,
  t,
  format,
  onSelectTask,
  onSelectDate,
  onRescheduleTask,
  onDragEnd,
}: DesktopTaskPillProps) {
  const handleKeyDown = useKeyboardReschedule(task, onRescheduleTask);
  const draggable = !!onRescheduleTask;
  const pillLabel = format('calendar.taskPillLabel', {
    title: task.title,
    date: dateLabel,
  });
  return (
    <button
      type="button"
      tabIndex={0}
      draggable={draggable}
      aria-label={pillLabel}
      aria-description={draggable ? t('calendar.keyboardHint') : undefined}
      onClick={(clickEvent) => {
        clickEvent.stopPropagation();
        if (onSelectTask) {
          onSelectTask(task.id);
        } else {
          onSelectDate(dateStr);
        }
      }}
      onKeyDown={(event) => {
        if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
          handleKeyDown(event);
        }
      }}
      onDragStart={(event) => {
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData(
          CALENDAR_TASK_DRAG_MIME,
          encodeCalendarTaskDrag(task.id, task.planned_date ?? task.due_date, !!task.planned_date, task.due_time),
        );
        applyCompactDragImage(event, { title: task.title, icon: '✦' });
        event.stopPropagation();
      }}
      onDragEnd={onDragEnd}
      className={`w-full text-start text-2xs leading-tight truncate px-1 py-0.5 rounded-r-control flex items-center gap-0.5 focus-ring-strong ${
        draggable ? 'cursor-grab active:cursor-grabbing' : ''
      } ${isOverdue ? 'chip-danger chip-danger-interactive' : 'bg-accent/10 text-accent'}`}
    >
      {/* pair red color with an icon so overdue is
          recognizable on grayscale / high-contrast themes and by
          screen readers. */}
      {isOverdue && (
        <>
          <WarningIcon className="w-2.5 h-2.5 shrink-0" aria-hidden="true" />
          <span className="sr-only">{t('today.overdue')}: </span>
        </>
      )}
      {task.recurrence ? RECURRENCE_SYMBOL : ''}
      <span className="truncate">{task.title}</span>
    </button>
  );
});

interface DesktopEventPillProps {
  event: UnifiedCalendarEvent;
  /// see DesktopTaskPillProps.dateStr — same memoization story.
  dateStr: string;
  dateLabel: string;
  t: (key: TranslationKey) => string;
  format: ReturnType<typeof useI18n>['format'];
  onSelectDate: (dateStr: string) => void;
}

export const DesktopEventPill = memo(function DesktopEventPillImpl({
  event,
  dateStr,
  dateLabel,
  t,
  format,
  onSelectDate,
}: DesktopEventPillProps) {
  const pillLabel = formatCalendarEventAccessibleLabel(event, {
    dateLabel,
    format,
    t,
  });
  return (
    <button
      type="button"
      tabIndex={0}
      aria-label={pillLabel}
      onClick={(clickEvent) => {
        clickEvent.stopPropagation();
        onSelectDate(dateStr);
      }}
      className="block w-full text-start text-2xs leading-tight truncate px-1.5 py-0.5 rounded-r-control text-text-primary focus-ring-strong"
      style={{
        // month-pill background tier routes through the
        // shared `eventColorStyles` helper so a theme retune lands here
        // in lockstep with every other event surface. The dense grid
        // wants a thinner 2 px inline-start border (the default is 3 px); the
        // helper's `borderWidth` knob lets us share both the background
        // mix and the border construction.
        ...eventColorStyles(event.color ?? null, 'soft', 2),
      }}
    >
      {eventTypeIcon(event.event_type) || (event.recurrence ? RECURRENCE_SYMBOL : '')}
      {event.all_day ? '' : event.start_time ? `${event.start_time} ` : ''}
      {event.title}
    </button>
  );
});
