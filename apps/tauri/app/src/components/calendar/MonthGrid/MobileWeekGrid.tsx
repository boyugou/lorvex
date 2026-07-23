import { useCallback, useEffect, useMemo, useState } from 'react';
import { WarningIcon } from '@/components/ui/icons';
import { eventColorStyles } from '@/lib/colorUtils';
import { isTaskOverdue } from '@/lib/format';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { formatCalendarDate } from '@/lib/dates/dateLocale';
import { useI18n } from '@/lib/i18n';

import { eventTypeIcon } from '../eventTypeIcon';
import {
  RECURRENCE_SYMBOL,
  addDays,
  toDateStr,
  weekAnchor,
} from '../calendarViewUtils';
import { formatCalendarEventAccessibleLabel } from '../calendarEventAccessibility';

import type { MonthGridProps } from './types';
import { TASK_STATUS } from '@lorvex/shared/types';
import type { Task } from '@/lib/ipc/tasks/models';

// Stable empty array — handed to consumers that need an iterable when a
// date has no tasks, so they never receive a fresh `[]` and accidentally
// retrigger memo/effect identity comparisons.
const EMPTY_TASKS: readonly Task[] = [];

/* ------------------------------------------------------------------ */
/* Mobile branch — one week at a time, tap-first, WCAG-sized targets.  */
/*                                                                     */
/* Extracted from the original MonthGrid.tsx during the M29      */
/* split. This view never participates in drag-reschedule, so it does  */
/* not depend on the desktop layout hook.                              */
/* ------------------------------------------------------------------ */

export function MobileWeekGrid({
  year,
  month,
  today,
  selectedDate,
  tasksByDate,
  eventsByDate,
  weekdayLabels,
  weekStartDay = 0,
  locale,
  t,
  onSelectDate,
  onSelectTask,
}: MonthGridProps) {
  const { format } = useI18n();
  const dayContext = useConfiguredDayContext();

  // Anchor the visible week on selectedDate || today, clamped to the
  // month the parent handed us so the initial render always shows the
  // expected range. Once the user navigates with prev/next we follow
  // their intent even if it crosses month boundaries — the parent
  // view mode is still "month", but at mobile widths showing one week
  // at a time is the only readable option.
  const initialAnchor = useMemo(() => {
    const candidate = selectedDate && selectedDate.startsWith(toDateStr(year, month, 1).slice(0, 7))
      ? selectedDate
      : today.startsWith(toDateStr(year, month, 1).slice(0, 7))
        ? today
        : toDateStr(year, month, 1);
    return weekAnchor(candidate, weekStartDay);
    // Intentionally only initialize from the first render; subsequent
    // updates to selectedDate come from tapping inside this view and
    // should NOT reset the visible week.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const [weekStart, setWeekStart] = useState<string>(initialAnchor);

  // When the parent navigates month (prev/next month buttons in the
  // header), snap the mobile week view to the first week of the new
  // month so the user sees something relevant.
  useEffect(() => {
    const firstOfMonth = toDateStr(year, month, 1);
    const currentMonthPrefix = weekStart.slice(0, 7);
    const parentMonthPrefix = firstOfMonth.slice(0, 7);
    if (currentMonthPrefix !== parentMonthPrefix) {
      setWeekStart(weekAnchor(firstOfMonth, weekStartDay));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [year, month, weekStartDay]);

  const weekDates = useMemo(() => {
    return Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));
  }, [weekStart]);

  const ariaLabelByDateStr = useMemo(() => {
    // `formatCalendarDate` routes through the shared memoized
    // formatter cache in `lib/dateLocale`, so swiping across weeks
    // reuses one `Intl.DateTimeFormat` instance per (locale,
    // options-shape) pair across the whole calendar surface.
    const labels: Record<string, string> = {};
    for (const d of weekDates) {
      labels[d] = formatCalendarDate(d, locale, {
        weekday: 'long', month: 'long', day: 'numeric',
      });
    }
    return labels;
  }, [weekDates, locale]);

  const weekRangeLabel = useMemo(() => {
    const first = weekDates[0];
    const last = weekDates[6];
    if (!first || !last) return '';
    const opts: Intl.DateTimeFormatOptions = { month: 'short', day: 'numeric' };
    return `${formatCalendarDate(first, locale, opts)} – ${formatCalendarDate(last, locale, opts)}`;
  }, [weekDates, locale]);

  // Hoist the per-date open-task partition out of render so we compute it
  // once per (tasksByDate) change instead of twice per visible day on every
  // render. Both the date-strip marker and the per-day section list read
  // through the same memoized map.
  const openTasksByDate = useMemo(() => {
    const map = new Map<string, Task[]>();
    for (const [date, tasks] of Object.entries(tasksByDate)) {
      map.set(date, tasks.filter((task) => task.status === TASK_STATUS.open));
    }
    return map;
  }, [tasksByDate]);

  const handlePrevWeek = useCallback(() => {
    setWeekStart((prev) => addDays(prev, -7));
  }, []);
  const handleNextWeek = useCallback(() => {
    setWeekStart((prev) => addDays(prev, 7));
  }, []);

  return (
    <div className="flex-1 min-h-0 flex flex-col">
      {/* Week selector header — 44×44 px tappable controls. */}
      <div className="flex items-center justify-between mb-2 shrink-0">
        <button
          type="button"
          onClick={handlePrevWeek}
          aria-label={t('calendar.previousWeek')}
          className="min-tap inline-flex items-center justify-center rounded-r-control text-text-muted hover:text-text-primary hover:bg-surface-2 active:bg-surface-3 transition-colors focus-ring-soft"
        >
          <span aria-hidden="true" className="text-lg">‹</span>
        </button>
        <div className="text-sm font-medium text-text-primary tabular-nums">{weekRangeLabel}</div>
        <button
          type="button"
          onClick={handleNextWeek}
          aria-label={t('calendar.nextWeek')}
          className="min-tap inline-flex items-center justify-center rounded-r-control text-text-muted hover:text-text-primary hover:bg-surface-2 active:bg-surface-3 transition-colors focus-ring-soft"
        >
          <span aria-hidden="true" className="text-lg">›</span>
        </button>
      </div>

      {/* Weekday label strip, aligned with the 7-col grid below. */}
      <div className="grid grid-cols-7 mb-1 shrink-0 border-b border-card pb-1.5">
        {weekdayLabels.map((label, idx) => (
          <div key={`wd-${idx}`} className="text-center text-xs font-medium text-text-muted py-1">
            {label}
          </div>
        ))}
      </div>

      {/* Day-of-week selector row (one tap-sized cell per day). */}
      <div className="grid grid-cols-7 gap-1 mb-3 shrink-0">
        {weekDates.map((dateStr) => {
          const day = Number(dateStr.slice(8, 10));
          const isToday = dateStr === today;
          const isSelected = dateStr === selectedDate;
          const dayEvents = eventsByDate[dateStr] ?? [];
          const openTasks = openTasksByDate.get(dateStr) ?? EMPTY_TASKS;
          const marker = openTasks.length + dayEvents.length;
          return (
            <button
              key={dateStr}
              type="button"
              onClick={() => onSelectDate(dateStr)}
              aria-label={`${ariaLabelByDateStr[dateStr] ?? dateStr}${isToday ? ` — ${t('nav.today')}` : ''}`}
              aria-pressed={isSelected}
              data-selected={isSelected || undefined}
              data-today={isToday || undefined}
              className="min-tap flex flex-col items-center justify-center rounded-r-control transition-colors hover:bg-surface-2 active:bg-surface-3 focus-ring-soft data-[selected]:bg-accent/15 data-[selected]:ring-1 data-[selected]:ring-accent/40"
            >
              {/* Inner glyph — sized to the today-circle pattern
                  (24px disc when `isToday`, plain text otherwise). The
                  outer button already owns the 44px tap target via
                  `min-tap`; layering another `min-tap` here inflated
                  the today disc to a 44px filled bubble (#4489). */}
              <span
                className={`inline-flex items-center justify-center rounded-full text-sm font-medium data-[today]:w-6 data-[today]:h-6 data-[today]:bg-accent data-[today]:text-on-accent data-[today]:font-semibold ${
                  !isToday ? 'text-text-primary' : ''
                }`}
                data-today={isToday || undefined}
              >
                {day}
              </span>
              {marker > 0 ? (
                <span
                  aria-hidden="true"
                  className="mt-0.5 w-1.5 h-1.5 rounded-full bg-accent"
                />
              ) : (
                <span aria-hidden="true" className="mt-0.5 w-1.5 h-1.5" />
              )}
            </button>
          );
        })}
      </div>

      {/* Per-day detail list for the visible week. Event pills tap
          to open the day panel (where the event form lives); task
          pills tap to open task detail if the caller wired it. Drag-
          reschedule is desktop-only — mobile users reschedule by
          opening the task/event form. */}
      <div className="flex-1 min-h-0 overflow-y-auto space-y-3">
        {weekDates.map((dateStr) => {
          const dayTasks = tasksByDate[dateStr] ?? EMPTY_TASKS;
          const dayEvents = eventsByDate[dateStr] ?? [];
          const openTasks = openTasksByDate.get(dateStr) ?? EMPTY_TASKS;
          const hasOverdue = dayTasks.some((task) => isTaskOverdue(task, dayContext) && task.status !== TASK_STATUS.completed);
          if (openTasks.length === 0 && dayEvents.length === 0) return null;
          return (
            <section key={`section-${dateStr}`} aria-label={ariaLabelByDateStr[dateStr] ?? dateStr}>
              <header className="text-xs font-medium text-text-muted mb-1 px-1">
                {ariaLabelByDateStr[dateStr] ?? dateStr}
              </header>
              <div className="space-y-1">
                {dayEvents.map((event) => {
                  const mobileDateLabel = ariaLabelByDateStr[dateStr] ?? dateStr;
                  const eventPillLabel = formatCalendarEventAccessibleLabel(event, {
                    dateLabel: mobileDateLabel,
                    format,
                    t,
                  });
                  return (
                    <button
                      key={event.id}
                      type="button"
                      onClick={() => onSelectDate(dateStr)}
                      aria-label={eventPillLabel}
                      className="min-tap flex items-center w-full text-start text-sm leading-snug truncate px-2 py-2 rounded-r-control text-text-primary focus-ring-strong"
                      style={eventColorStyles(event.color ?? null, 'medium')}
                    >
                      <span className="truncate">
                        {eventTypeIcon(event.event_type) || (event.recurrence ? RECURRENCE_SYMBOL : '')}
                        {event.all_day ? '' : event.start_time ? `${event.start_time} ` : ''}
                        {event.title}
                      </span>
                    </button>
                  );
                })}
                {openTasks.map((task) => {
                  const isOverduePill =
                    hasOverdue && isTaskOverdue(task, dayContext) && task.status !== TASK_STATUS.completed;
                  const mobileDateLabel = ariaLabelByDateStr[dateStr] ?? dateStr;
                  const taskPillLabel = format('calendar.taskPillLabel', {
                    title: task.title,
                    date: mobileDateLabel,
                  });
                  return (
                    <button
                      key={task.id}
                      type="button"
                      onClick={() => {
                        if (onSelectTask) {
                          onSelectTask(task.id);
                        } else {
                          onSelectDate(dateStr);
                        }
                      }}
                      aria-label={taskPillLabel}
                      className={`flex items-center w-full text-start text-sm leading-snug px-2 py-2 rounded-r-control focus-ring-strong ${
                        isOverduePill ? 'chip-danger chip-danger-interactive' : 'bg-accent/10 text-accent'
                      }`}
                    >
                      {isOverduePill && (
                        <>
                          <WarningIcon className="w-4 h-4 shrink-0 me-1" aria-hidden="true" />
                          <span className="sr-only">{t('today.overdue')}: </span>
                        </>
                      )}
                      {task.recurrence ? <span className="me-1" aria-hidden="true">{RECURRENCE_SYMBOL}</span> : null}
                      <span className="truncate">{task.title}</span>
                    </button>
                  );
                })}
              </div>
            </section>
          );
        })}
      </div>
    </div>
  );
}
