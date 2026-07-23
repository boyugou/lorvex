import type { DragEvent as ReactDragEvent } from 'react';

import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { TASK_STATUS } from '@lorvex/shared/types';
import { WeekTimelineEventChip } from './WeekTimelineEventChip';
import { WeekTimelineTaskChip } from './WeekTimelineTaskChip';
import {
  computeWeekTimelineSlots,
  WEEK_TIMELINE_DEFAULT_EVENT_DURATION,
  WEEK_TIMELINE_DEFAULT_TASK_DURATION,
  weekTimelineMinutesToTop,
  WEEK_TIMELINE_HOUR_COUNT,
  WEEK_TIMELINE_ROW_HEIGHT,
  WEEK_TIMELINE_TOTAL_HEIGHT,
} from './weekTimelineLayout';

interface WeekDayColumnProps {
  dateStr: string;
  dateLabel: string;
  isToday: boolean;
  isWeekend: boolean;
  /** Minutes since midnight in the user's timezone, or null when this is not the today column. */
  currentTimeMinutes: number | null;
  events: UnifiedCalendarEvent[];
  tasks: Task[];
  isDragOver: boolean;
  untitledEventLabel: string;
  t: (key: TranslationKey) => string;
  onSelectDate: (date: string) => void;
  onSelectTask: (id: string) => void;
  onDragOver: (event: ReactDragEvent<HTMLDivElement>) => void;
  onDragLeave: (event: ReactDragEvent<HTMLDivElement>) => void;
  onDrop: (event: ReactDragEvent<HTMLDivElement>) => void;
}

/**
 * Single day's column on the week timeline.
 *
 * Hosts:
 *  - horizontal hour gridlines (subtle every-hour rule + half-hour
 *    tick), painted with `::before` would normally be cheaper, but a
 *    static array keeps the chip-layout math obvious. The line array
 *    is memo-safe — its size is the compile-time HOUR_COUNT.
 *  - the today column's now-indicator (red horizontal line spanning
 *    the column at the current minute).
 *  - timed event chips, absolutely positioned by their start/duration.
 *  - timed task chips (tasks with `due_time`), similarly positioned.
 *
 * The column is a drop target: dropping a task here reschedules it to
 * this date, with the `due_time` inferred from the drop's Y offset (the
 * Y→time math lives in `WeekTimelineGrid`, which owns the body geometry).
 */
export function WeekDayColumn({
  dateStr,
  dateLabel,
  isToday,
  isWeekend,
  currentTimeMinutes,
  events,
  tasks,
  isDragOver,
  untitledEventLabel,
  t,
  onSelectDate,
  onSelectTask,
  onDragOver,
  onDragLeave,
  onDrop,
}: WeekDayColumnProps) {
  // Filter tasks: timed (due_time present, open status) appear on the
  // grid; everything else falls through to the all-day strip handled
  // by the parent component.
  const timedTasks = tasks.filter(
    (task) => task.status === TASK_STATUS.open && task.due_time,
  );

  const timedEvents = events.filter((event) => !event.all_day && event.start_time);
  const slotAssignments = computeWeekTimelineSlots([
    ...timedEvents.map((event) => ({
      id: event.id,
      start: event.start_time,
      end: event.end_time,
      fallbackDurationMinutes: WEEK_TIMELINE_DEFAULT_EVENT_DURATION,
    })),
    ...timedTasks.map((task) => ({
      id: task.id,
      start: task.due_time,
      end: null,
      fallbackDurationMinutes: task.estimated_minutes ?? WEEK_TIMELINE_DEFAULT_TASK_DURATION,
    })),
  ]);

  return (
    // Day column is a drop target + chip canvas, not an interactive
    // element itself — selection happens via the dedicated header
    // button in `WeekTimelineGrid`. The drag handlers are window-chrome
    // affordances for HTML5 DnD; `jsx-a11y/click-events-have-key-events`
    // would otherwise flag them as a missing keyboard equivalent, but
    // keyboard reschedule lives in the per-task chip's own listener.
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <div
      data-date={dateStr}
      data-today={isToday || undefined}
      data-dragover={isDragOver || undefined}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
      className={`relative flex-1 min-w-0 border-e border-surface-3 transition-colors duration-100 ${
        isWeekend ? 'bg-surface-1/40' : 'bg-surface-1/10'
      } data-[today]:bg-[var(--accent-tint-xxs)] data-[dragover]:bg-accent/5 data-[dragover]:ring-2 data-[dragover]:ring-inset data-[dragover]:ring-accent/40`}
      style={{ height: WEEK_TIMELINE_TOTAL_HEIGHT }}
    >
      {/* Hour grid lines. The full-line every hour + half-line every
          half-hour rhythm makes the timeline scannable; reading the
          grid alone tells the user "9:30 starts here" without a
          visible chip label. `aria-hidden` because the time-axis
          carries the announcement. */}
      <div aria-hidden="true" className="absolute inset-0 pointer-events-none">
        {Array.from({ length: WEEK_TIMELINE_HOUR_COUNT }, (_, hourIndex) => {
          const top = hourIndex * WEEK_TIMELINE_ROW_HEIGHT;
          return (
            <div key={hourIndex}>
              <div
                className="absolute inset-x-0 border-t border-surface-3"
                style={{ top }}
              />
              {/* Half-hour tick — lighter, only when the row is tall
                  enough to make the subdivision useful. */}
              {WEEK_TIMELINE_ROW_HEIGHT >= 40 && (
                <div
                  className="absolute inset-x-0 border-t border-surface-3/30"
                  style={{ top: top + WEEK_TIMELINE_ROW_HEIGHT / 2 }}
                />
              )}
            </div>
          );
        })}
      </div>

      {/* Today's now-indicator. The 8-pixel dot at the start lets the
          user pick out which column is today even when the line itself
          gets occluded by an in-progress meeting chip. `z-[var(--z-now-indicator)]`
          stacks above the chips. */}
      {isToday && currentTimeMinutes !== null && (
        <NowIndicator currentTimeMinutes={currentTimeMinutes} t={t} />
      )}

      {/* Timed event chips. */}
      {timedEvents.map((event) => {
        const slot = slotAssignments.get(event.id);
        return (
          <WeekTimelineEventChip
            key={event.id}
            event={event}
            dateLabel={dateLabel}
            untitledLabel={untitledEventLabel}
            slotIndex={slot?.index ?? 0}
            slotCount={slot?.count ?? 1}
            onSelect={() => onSelectDate(dateStr)}
          />
        );
      })}

      {/* Timed task chips. */}
      {timedTasks.map((task) => {
        const slot = slotAssignments.get(task.id);
        return (
          <WeekTimelineTaskChip
            key={task.id}
            task={task}
            dateLabel={dateLabel}
            t={t}
            slotIndex={slot?.index ?? 0}
            slotCount={slot?.count ?? 1}
            onSelect={() => onSelectTask(task.id)}
          />
        );
      })}
    </div>
  );
}

interface NowIndicatorProps {
  currentTimeMinutes: number;
  t: (key: TranslationKey) => string;
}

function NowIndicator({ currentTimeMinutes, t }: NowIndicatorProps) {
  // Compute Y once at render. The parent column re-renders on minute
  // tick so this stays in sync without needing its own timer.
  const top = weekTimelineMinutesToTop(currentTimeMinutes);

  return (
    <div
      role="presentation"
      aria-label={t('calendar.currentTime')}
      className="absolute inset-x-0 z-[var(--z-now-indicator)] pointer-events-none"
      style={{ top }}
    >
      <div className="relative h-px bg-danger/80 shadow-[0_0_4px_var(--danger-tint-md)]">
        <span className="absolute -translate-y-1/2 start-0 w-2 h-2 rounded-full bg-danger" />
      </div>
    </div>
  );
}
