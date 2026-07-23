import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type DragEvent as ReactDragEvent,
} from 'react';

import { formatCalendarDate } from '@/lib/dates/dateLocale';
import { getMinutesSinceMidnightInTimezone, useConfiguredDayContext } from '@/lib/dayContext';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import { toast } from '@/lib/notifications/toast';
import type { TranslationKey } from '@/lib/i18n';
import { addDays, CALENDAR_TASK_DRAG_MIME } from '../calendarViewUtils';
import { resolveWeekGridDrop, resolveWeekTimelineDropTime } from '../weekGridDrop.logic';
import type { WeekGridTaskReschedule } from '../weekGridTypes';
import { WeekAllDayStrip } from './WeekAllDayStrip';
import { WeekDayColumn } from './WeekDayColumn';
import { WeekTimeAxis } from './WeekTimeAxis';
import {
  WEEK_TIMELINE_MIN_WIDTH,
  WEEK_TIMELINE_TIME_AXIS_WIDTH,
  weekTimelineInitialScrollTop,
  weekTimelineMinutesToTimeString,
  weekTimelineScrollAnchorItems,
  weekTimelineTopToMinutes,
} from './weekTimelineLayout';

interface WeekTimelineGridProps {
  weekStart: string;
  today: string;
  selectedDate: string | null;
  tasksByDate: Record<string, Task[]>;
  eventsByDate: Record<string, UnifiedCalendarEvent[]>;
  weekdayLabels: string[];
  locale: string;
  t: (key: TranslationKey) => string;
  onSelectDate: (date: string) => void;
  onSelectTask: (id: string) => void;
  onInvalidate: () => void;
  onRescheduleTask?: WeekGridTaskReschedule;
}

/**
 * Full-week timeline view.
 *
 * Layout:
 *   ┌─ day header row (sticky-feeling, drives column width) ─┐
 *   ├─ all-day strip (full-day events + untimed tasks)       │
 *   └─ scrollable timeline body                              │
 *       ├─ time axis (00:00 – 23:00)                         │
 *       └─ 7 day columns with absolute-positioned chips      ┘
 *
 * The body auto-scrolls to the selected day's first timed item when
 * one exists; otherwise it anchors to the visible week's first timed
 * item before falling back to "now".
 *
 * Drag-and-drop infers both day and time from the drop, matching the
 * day timeline: the target column gives the date, and the drop's Y
 * offset (inverted through the shared `timelineLayout` geometry) gives
 * a snapped `due_time`. A drop indicator line tracks the snap target
 * during dragover. A drop is a no-op only when both the day and the
 * inferred time match the task's current values.
 */
export function WeekTimelineGrid({
  weekStart,
  today,
  selectedDate,
  tasksByDate,
  eventsByDate,
  weekdayLabels,
  locale,
  t,
  onSelectDate,
  onSelectTask,
  onInvalidate: _onInvalidate,
  onRescheduleTask,
}: WeekTimelineGridProps) {
  // 7-day descriptor list, mirrors the prior WeekGrid's `weekDays`
  // shape so downstream filters (weekend / today highlights) stay
  // semantics-equivalent.
  const weekDays = useMemo(
    () =>
      Array.from({ length: 7 }, (_, index) => {
        const dateStr = addDays(weekStart, index);
        const date = new Date(`${dateStr}T00:00:00Z`);
        const dow = date.getUTCDay();
        return {
          dateStr,
          isToday: dateStr === today,
          isWeekend: dow === 0 || dow === 6,
          dayNum: date.getUTCDate(),
          dow,
        };
      }),
    [today, weekStart],
  );

  const untitledEventLabel = t('calendar.untitledEvent');

  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const scrollAnchorItems = useMemo(
    () =>
      weekTimelineScrollAnchorItems({
        selectedDate,
        weekDates: weekDays.map((day) => day.dateStr),
        eventsByDate,
        tasksByDate,
      }),
    [eventsByDate, selectedDate, tasksByDate, weekDays],
  );
  const initialScrollSignature = useMemo(
    () =>
      [
        selectedDate ?? 'none',
        ...scrollAnchorItems.map((item) => `${item.id}:${item.start ?? ''}:${item.end ?? ''}`),
      ].join('|'),
    [scrollAnchorItems, selectedDate],
  );
  const lastInitialScrollSignatureRef = useRef<string | null>(null);

  // Re-anchor when the selected date or async-loaded timed items
  // change. Future weeks should land on their first real appointment;
  // otherwise the grid falls back to the current-time zone.
  const dayContext = useConfiguredDayContext();
  useEffect(() => {
    const node = scrollContainerRef.current;
    if (!node) return;
    const scrollKey = `${dayContext.timezone}|${initialScrollSignature}`;
    if (lastInitialScrollSignatureRef.current === scrollKey) return;
    lastInitialScrollSignatureRef.current = scrollKey;
    const minutes = getMinutesSinceMidnightInTimezone(dayContext.timezone);
    node.scrollTop = weekTimelineInitialScrollTop({
      currentMinutes: minutes,
      selectedDayItems: scrollAnchorItems,
    });
  }, [dayContext.timezone, initialScrollSignature, scrollAnchorItems]);

  // Current-time minute counter; ticks once a minute so the today
  // column's now-indicator drifts down smoothly.
  const [nowMinutes, setNowMinutes] = useState<number>(() =>
    getMinutesSinceMidnightInTimezone(dayContext.timezone),
  );
  useEffect(() => {
    const id = window.setInterval(() => {
      setNowMinutes(getMinutesSinceMidnightInTimezone(dayContext.timezone));
    }, 60_000);
    return () => window.clearInterval(id);
  }, [dayContext.timezone]);

  // --- Drag-and-drop reschedule (column gives the day, drop Y gives the time) ---
  const [dragOverDate, setDragOverDate] = useState<string | null>(null);
  // Snapped top-pixel of the drop indicator within the timeline body, or
  // null when no drag is hovering. Drives the indicator line + its label.
  const [dropIndicatorTop, setDropIndicatorTop] = useState<number | null>(null);
  const onRescheduleRef = useRef(onRescheduleTask);
  useEffect(() => {
    onRescheduleRef.current = onRescheduleTask;
  }, [onRescheduleTask]);
  // Guards against double-drops on a task whose previous reschedule
  // is still in flight, matching the prior WeekGrid contract.
  const pendingRef = useRef<Set<string>>(new Set());
  // Cache the scroll body's bounding rect for the duration of a drag so the
  // Y→time math doesn't call `getBoundingClientRect()` on every dragover
  // (~60/s). Cleared on dragleave/drop. The body is the same element whose
  // geometry `weekTimelineMinutesToTop` addresses, so inverting a drop's Y
  // against it (minus rect.top, plus scrollTop) is correct by construction.
  const dragRectCacheRef = useRef<DOMRect | null>(null);

  // Map a drop's clientY to a snapped time on the shared timeline geometry.
  // The column (dataset.date) supplies the day; this supplies the time.
  const computeDropTime = useCallback((clientY: number): { top: number; timeStr: string } | null => {
    const body = scrollContainerRef.current;
    if (!body) return null;
    let rect = dragRectCacheRef.current;
    if (!rect) {
      rect = body.getBoundingClientRect();
      dragRectCacheRef.current = rect;
    }
    const relativeY = clientY - rect.top + body.scrollTop;
    return resolveWeekTimelineDropTime(relativeY);
  }, []);

  const handleDragOver = useCallback(
    (event: ReactDragEvent<HTMLDivElement>) => {
      if (!event.dataTransfer.types.includes(CALENDAR_TASK_DRAG_MIME)) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = 'move';
      const dateStr = event.currentTarget.dataset.date;
      if (!dateStr) return;
      setDragOverDate((prev) => (prev === dateStr ? prev : dateStr));
      const result = computeDropTime(event.clientY);
      if (result) setDropIndicatorTop(result.top);
    },
    [computeDropTime],
  );

  const handleDragLeave = useCallback(
    (event: ReactDragEvent<HTMLDivElement>) => {
      if (event.currentTarget.contains(event.relatedTarget as Node)) return;
      dragRectCacheRef.current = null;
      setDropIndicatorTop(null);
      const dateStr = event.currentTarget.dataset.date;
      if (!dateStr) return;
      setDragOverDate((prev) => (prev === dateStr ? null : prev));
    },
    [],
  );

  const handleDrop = useCallback(
    (event: ReactDragEvent<HTMLDivElement>) => {
      event.preventDefault();
      setDragOverDate(null);
      setDropIndicatorTop(null);
      const dateStr = event.currentTarget.dataset.date;
      const dropTime = computeDropTime(event.clientY);
      dragRectCacheRef.current = null;
      if (!dateStr || !dropTime) return;
      const reschedule = onRescheduleRef.current;
      const outcome = resolveWeekGridDrop(
        event.dataTransfer.getData(CALENDAR_TASK_DRAG_MIME),
        dateStr,
        dropTime.timeStr,
        !!reschedule,
      );
      if (outcome.kind === 'ignore') return;
      if (pendingRef.current.has(outcome.taskId)) {
        toast.info(t('toast.dropIgnoredPending'), undefined, `drop-pending:${outcome.taskId}`);
        return;
      }
      pendingRef.current.add(outcome.taskId);
      const settle = () => pendingRef.current.delete(outcome.taskId);
      try {
        const result = reschedule?.(
          outcome.taskId,
          outcome.newDate,
          outcome.oldDate,
          outcome.oldTime,
          outcome.dueTime,
          outcome.hasPlannedDate,
        );
        if (result && typeof (result as Promise<unknown>).then === 'function') {
          void (result as Promise<unknown>).finally(settle);
        } else {
          queueMicrotask(settle);
        }
      } catch {
        settle();
      }
    },
    [computeDropTime, t],
  );

  return (
    <div className="h-full min-h-0 rounded-r-card border border-surface-3 overflow-x-auto overflow-y-hidden overscroll-x-contain bg-surface-1">
      <div
        className="flex h-full min-h-0 flex-col"
        style={{ minWidth: WEEK_TIMELINE_MIN_WIDTH }}
      >
        {/* --- Day header row --- */}
        <div className="shrink-0 flex border-b border-surface-3 bg-surface-2/40">
          <div
            aria-hidden="true"
            className="shrink-0 border-e border-surface-3"
            style={{ width: WEEK_TIMELINE_TIME_AXIS_WIDTH }}
          />
          {weekDays.map(({ dateStr, dayNum, dow, isToday, isWeekend }, index) => {
            const isSelected = dateStr === selectedDate;
            const weekdayLabel = weekdayLabels[index];
            const headerLabel = formatCalendarDate(dateStr, locale, {
              weekday: 'long',
              month: 'long',
              day: 'numeric',
            });
            return (
              <button
                type="button"
                key={dateStr}
                onClick={() => onSelectDate(dateStr)}
                data-today={isToday || undefined}
                data-selected={isSelected || undefined}
                aria-label={`${headerLabel}${isToday ? ` — ${t('nav.today')}` : ''}`}
                aria-pressed={isSelected}
                className={`flex-1 min-w-0 border-e border-surface-3 px-2 py-2 text-center transition-colors hover:bg-surface-2 focus-ring-soft ${
                  isWeekend ? 'bg-surface-1/30' : ''
                } data-[selected]:bg-accent/10 data-[selected]:ring-2 data-[selected]:ring-inset data-[selected]:ring-accent/40`}
              >
                <p
                  className="text-2xs font-medium text-text-muted uppercase tracking-wide"
                  aria-hidden="true"
                >
                  {weekdayLabel ?? new Intl.DateTimeFormat(locale, { weekday: 'short' }).format(
                    new Date(Date.UTC(2024, 0, 7 + dow)),
                  )}
                </p>
                <div
                  aria-hidden="true"
                  data-today={isToday || undefined}
                  className="mx-auto mt-0.5 w-7 h-7 rounded-full flex items-center justify-center text-sm font-medium data-[today]:bg-accent data-[today]:text-on-accent"
                >
                  {dayNum}
                </div>
              </button>
            );
          })}
        </div>

        {/* --- All-day strip --- */}
        <WeekAllDayStrip
          weekDays={weekDays}
          eventsByDate={eventsByDate}
          tasksByDate={tasksByDate}
          untitledEventLabel={untitledEventLabel}
          t={t}
          onSelectTask={onSelectTask}
          onSelectDate={onSelectDate}
        />

        {/* --- Scrollable timeline body --- */}
        <div
          ref={scrollContainerRef}
          className="flex-1 min-h-0 overflow-y-auto overscroll-contain"
        >
          <div className="flex relative">
            <WeekTimeAxis />
            {/* Drop indicator: a horizontal snap-target line spanning the day
                columns (offset past the time axis), with a time label. Stacks
                above the chips at the canonical "hover overlay above sticky"
                tier so it outranks an in-progress meeting/task at that Y, while
                the now-indicator stays below. */}
            {dropIndicatorTop != null && (
              <div
                className="absolute end-0 h-0.5 bg-accent/60 rounded-full pointer-events-none z-[calc(var(--z-popover)-1)]"
                style={{ top: dropIndicatorTop, insetInlineStart: WEEK_TIMELINE_TIME_AXIS_WIDTH }}
              >
                <span className="absolute -top-2.5 start-0.5 text-3xs text-accent font-medium tabular-nums">
                  {weekTimelineMinutesToTimeString(weekTimelineTopToMinutes(dropIndicatorTop))}
                </span>
              </div>
            )}
            {weekDays.map(({ dateStr, isToday, isWeekend }) => {
              const dateLabel = formatCalendarDate(dateStr, locale, {
                weekday: 'long',
                month: 'long',
                day: 'numeric',
              });
              return (
                <WeekDayColumn
                  key={dateStr}
                  dateStr={dateStr}
                  dateLabel={dateLabel}
                  isToday={isToday}
                  isWeekend={isWeekend}
                  currentTimeMinutes={isToday ? nowMinutes : null}
                  events={eventsByDate[dateStr] ?? []}
                  tasks={tasksByDate[dateStr] ?? []}
                  isDragOver={dragOverDate === dateStr}
                  untitledEventLabel={untitledEventLabel}
                  t={t}
                  onSelectDate={onSelectDate}
                  onSelectTask={onSelectTask}
                  onDragOver={handleDragOver}
                  onDragLeave={handleDragLeave}
                  onDrop={handleDrop}
                />
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
