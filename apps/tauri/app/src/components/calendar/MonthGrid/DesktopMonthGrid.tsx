import { useCallback, useEffect, useRef, useState } from 'react';
import { isSpuriousDragLeave } from '@/lib/dragLeave';
import { isTaskOverdue } from '@/lib/format';
import { getMinutesSinceMidnightInTimezone, useConfiguredDayContext } from '@/lib/dayContext';
import { useI18n } from '@/lib/i18n';
import { CheckIcon } from '@/components/ui/icons';

import {
  CALENDAR_TASK_DRAG_MIME,
  addDays,
  decodeCalendarTaskDrag,
  toDateStr,
} from '../calendarViewUtils';

import { DesktopEventPill, DesktopTaskPill } from './pills';
import type { CellClassification, MonthGridProps } from './types';
import { useDesktopMonthLayout } from './useDesktopMonthLayout';
import { TASK_STATUS } from '@lorvex/shared/types';

/* ------------------------------------------------------------------ */
/* Desktop branch — dense month grid.                                  */
/*                                                                     */
/* Extracted from the original MonthGrid.tsx during the M29      */
/* split. The hook ownership of layout math + classification lives in  */
/* `useDesktopMonthLayout`; the JSX renders cells against that         */
/* precomputed snapshot.                                               */
/* ------------------------------------------------------------------ */

const EMPTY_CELL: CellClassification = {
  hasOverdue: false,
  openTasks: [],
  completedTasks: [],
  shownEvents: [],
  shownTasks: [],
  totalHidden: 0,
};

export function DesktopMonthGrid({
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
  onRescheduleTask,
}: MonthGridProps) {
  const { formatNumber, format } = useI18n();
  const dayContext = useConfiguredDayContext();
  const currentTimeFraction = useCurrentTimeFraction(dayContext.timezone);
  const [dragOverDate, setDragOverDate] = useState<string | null>(null);
  const { gridRef, cells, numRows, ariaLabelByDateStr, classificationByDateStr } =
    useDesktopMonthLayout({
      year,
      month,
      weekStartDay,
      locale,
      tasksByDate,
      eventsByDate,
      dayContext,
    });

  // Stable handlers so pill props are referentially stable, letting
  // React.memo on DesktopTaskPill / DesktopEventPill skip re-render
  // when only sibling cells changed (calendar drag-hover hot path).
  const handleSelectDate = useCallback(
    (dateStr: string) => {
      onSelectDate(dateStr);
    },
    [onSelectDate],
  );
  const handleSelectTask = useCallback(
    (taskId: string) => {
      onSelectTask?.(taskId);
    },
    [onSelectTask],
  );
  const handlePillDragEnd = useCallback(() => {
    setDragOverDate(null);
  }, []);

  // stable cell drag handlers. Read the target date from
  // `data-date` on `event.currentTarget.dataset` instead of capturing
  // `dateStr` in a per-cell closure. Without this, every cell
  // re-rendered on every drag-over (42 cells × 60 events/sec spawned
  // ~2500 new closures/sec). The latest reschedule callback flows
  // through a ref so the handler identity stays stable across
  // re-renders that arrive from prop changes higher up.
  const onRescheduleTaskRef = useRef(onRescheduleTask);
  useEffect(() => {
    onRescheduleTaskRef.current = onRescheduleTask;
  }, [onRescheduleTask]);

  const handleCellDragOver = useCallback((event: React.DragEvent<HTMLDivElement>) => {
    if (!event.dataTransfer.types.includes(CALENDAR_TASK_DRAG_MIME)) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
    const dateStr = event.currentTarget.dataset.date;
    if (!dateStr) return;
    setDragOverDate((prev) => (prev === dateStr ? prev : dateStr));
  }, []);

  const handleCellDragLeave = useCallback((event: React.DragEvent<HTMLDivElement>) => {
    if (isSpuriousDragLeave(event)) return;
    const dateStr = event.currentTarget.dataset.date;
    if (!dateStr) return;
    setDragOverDate((prev) => (prev === dateStr ? null : prev));
  }, []);

  const handleCellDrop = useCallback((event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setDragOverDate(null);
    const dateStr = event.currentTarget.dataset.date;
    const reschedule = onRescheduleTaskRef.current;
    if (!dateStr || !reschedule) return;
    const payload = decodeCalendarTaskDrag(event.dataTransfer.getData(CALENDAR_TASK_DRAG_MIME));
    if (!payload) return;
    // Branch the drop explicitly so the user gets feedback on every
    // outcome instead of a silent no-op when they drop onto the source
    // day. Same-day drop swallows without animation.
    if (payload.oldDate === dateStr) return;
    reschedule(payload.id, dateStr, payload.oldDate, payload.hasPlannedDate);
  }, []);

  return (
    <>
      <div className="grid grid-cols-7 mb-1 shrink-0 border-b border-card pb-1.5">
        {weekdayLabels.map((label, idx) => (
          <div key={`wd-${idx}`} className="text-center text-2xs font-medium text-text-muted py-1">
            {label}
          </div>
        ))}
      </div>
      <div
        ref={gridRef}
        className="grid grid-cols-7 gap-px bg-surface-3 rounded-r-card overflow-hidden border border-surface-3 flex-1 min-h-0"
        style={{ gridTemplateRows: `repeat(${numRows}, minmax(0, 1fr))` }}
      >
        {cells.map((day, index) => {
          const dow = (index % 7 + weekStartDay) % 7;
          const isWeekend = dow === 0 || dow === 6;
          if (!day) return <div key={`pad-${index}`} className={isWeekend ? 'bg-surface-1/60' : 'bg-surface-1'} />;
          const dateStr = toDateStr(year, month, day);
          const dayEvents = eventsByDate[dateStr] ?? [];
          const isToday = dateStr === today;
          const isPast = dateStr < today;
          const isSelected = dateStr === selectedDate;
          // O(1) lookup into the precomputed cell map.
          const cellState = classificationByDateStr[dateStr] ?? EMPTY_CELL;
          const { hasOverdue, openTasks, completedTasks, shownEvents, shownTasks, totalHidden } =
            cellState;

          const isDragOver = dragOverDate === dateStr;

          return (
            // Keep the cell as a non-interactive drag/drop surface.
            // Date selection belongs to the header button so task and
            // event pill buttons never sit inside a button-like ancestor.
            <div
              key={dateStr}
              role="group"
              aria-label={ariaLabelByDateStr[dateStr] ?? dateStr}
              data-date={dateStr}
              onDragOver={handleCellDragOver}
              onDragLeave={handleCellDragLeave}
              onDrop={handleCellDrop}
              data-selected={isSelected || undefined}
              data-dragover={isDragOver || undefined}
              data-today={isToday || undefined}
              data-past={isPast || undefined}
              className={`relative ${isWeekend ? 'bg-surface-1/60' : 'bg-surface-1'} p-2 text-start transition-colors overflow-hidden hover:bg-surface-2 data-[past]:bg-surface-1/30 data-[past]:opacity-[0.96] data-[today]:[box-shadow:inset_0_0_0_1px_var(--accent-tint-md)] data-[selected]:bg-accent/8 data-[selected]:ring-1 data-[selected]:ring-inset data-[selected]:ring-accent/40 data-[dragover]:ring-1 data-[dragover]:ring-accent/40 data-[dragover]:bg-accent/5`}
            >
              {isToday && currentTimeFraction != null && (
                <div
                  aria-hidden="true"
                  className="pointer-events-none absolute inset-x-1 z-[var(--z-now-indicator)] h-px bg-accent/80"
                  style={{
                    top: `calc(${(currentTimeFraction * 100).toFixed(3)}% )`,
                    boxShadow: '0 0 6px var(--accent-tint-md)',
                  }}
                />
              )}
              <div className="flex items-center gap-1 mb-1">
                <button
                  type="button"
                  data-day-select
                  data-today={isToday || undefined}
                  data-selected={isSelected || undefined}
                  aria-label={`${ariaLabelByDateStr[dateStr] ?? dateStr}${isToday ? ` — ${t('nav.today')}` : ''}`}
                  aria-current={isToday ? 'date' : undefined}
                  aria-pressed={isSelected}
                  onClick={() => onSelectDate(dateStr)}
                  onKeyDown={(event) => {
                    if (!onRescheduleTask || !event.shiftKey) return;
                    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
                    const firstTask = openTasks[0];
                    if (!firstTask) return;
                    const effectiveDate = firstTask.planned_date ?? firstTask.due_date;
                    if (!effectiveDate) return;
                    event.preventDefault();
                    event.stopPropagation();
                    const delta = event.key === 'ArrowLeft' ? -1 : 1;
                    const newDate = addDays(effectiveDate, delta);
                    onRescheduleTask(firstTask.id, newDate, effectiveDate, !!firstTask.planned_date);
                  }}
                  className={`inline-flex items-center justify-center w-6 h-6 rounded-full text-xs font-medium focus-ring-strong transition-transform active:scale-[0.96] data-[today]:bg-accent data-[today]:text-on-accent data-[today]:font-semibold data-[selected]:ring-2 data-[selected]:ring-inset data-[selected]:ring-accent/60 ${
                    !isToday ? (isPast ? 'text-text-muted' : 'text-text-primary') : ''
                  }`}
                >
                  {day}
                </button>
                {(openTasks.length > 0 || dayEvents.length > 0) && (
                  <span className="text-3xs text-text-muted tabular-nums">
                    {formatNumber(openTasks.length + dayEvents.length)}
                  </span>
                )}
                {completedTasks.length > 0 && (
                  <span className="text-3xs text-success tabular-nums inline-flex items-center gap-px"><CheckIcon className="w-2 h-2" />{formatNumber(completedTasks.length)}</span>
                )}
              </div>
              <div className="space-y-0.5">
                {shownEvents.map((event) => (
                  <DesktopEventPill
                    key={event.id}
                    event={event}
                    dateStr={dateStr}
                    dateLabel={ariaLabelByDateStr[dateStr] ?? dateStr}
                    t={t}
                    format={format}
                    // On desktop there is no dedicated event-detail
                    // surface hooked up here; selecting the date opens
                    // the DayPanel where the event can be edited.
                    // Matches the pre-audit behaviour where the whole
                    // cell was a single selector.
                    onSelectDate={handleSelectDate}
                  />
                ))}
                {shownTasks.map((task) => {
                  const isOverduePill =
                    hasOverdue && isTaskOverdue(task, dayContext) && task.status !== TASK_STATUS.completed;
                  return (
                    <DesktopTaskPill
                      key={task.id}
                      task={task}
                      dateStr={dateStr}
                      dateLabel={ariaLabelByDateStr[dateStr] ?? dateStr}
                      isOverdue={isOverduePill}
                      t={t}
                      format={format}
                      onRescheduleTask={onRescheduleTask}
                      onDragEnd={handlePillDragEnd}
                      onSelectTask={onSelectTask ? handleSelectTask : undefined}
                      onSelectDate={handleSelectDate}
                    />
                  );
                })}
                {totalHidden > 0 ? (
                  <div className="text-2xs text-text-muted px-1">+{formatNumber(totalHidden)} {t('calendar.more')}</div>
                ) : null}
              </div>
            </div>
          );
        })}
      </div>
    </>
  );
}

/**
 * Fraction (0..1) of the way through today in the user's timezone,
 * ticking once per minute. Drives the horizontal accent line on
 * today's month-grid cell so the user sees "we are here in the day"
 * at a glance.
 */
function useCurrentTimeFraction(timezone: string): number {
  const [minutes, setMinutes] = useState(() => getMinutesSinceMidnightInTimezone(timezone));
  useEffect(() => {
    setMinutes(getMinutesSinceMidnightInTimezone(timezone));
    const id = window.setInterval(() => {
      setMinutes(getMinutesSinceMidnightInTimezone(timezone));
    }, 60_000);
    return () => window.clearInterval(id);
  }, [timezone]);
  return Math.max(0, Math.min(1, minutes / 1440));
}
