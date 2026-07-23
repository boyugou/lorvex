import { useEffect, useMemo, useRef } from 'react';
import { eventColorStyles } from '@/lib/colorUtils';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import { isDueOverdue } from '@/lib/format';
import { eventTypeIcon } from '../calendar/eventTypeIcon';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { parseTimeToMinutes } from '@/lib/timeUtils';
import { useCurrentTime } from '@/lib/time/useCurrentTime';
import type { PositionedEvent, PositionedTask } from '@/lib/timeline/types';
import {
  formatWeekTimelineDayLabel,
  WEEK_TIMELINE_DEFAULT_EVENT_DURATION,
  WEEK_TIMELINE_HOUR_COUNT,
  WEEK_TIMELINE_HOUR_END,
  WEEK_TIMELINE_HOUR_START,
  WEEK_TIMELINE_ROW_HEIGHT,
  weekTimelineDurationToHeight,
  weekTimelineEventGeometry,
  weekTimelineInitialScrollTopForItems,
  weekTimelineLaneStyle,
  weekTimelineMinutesToOffset,
  weekTimelineScrollAnchorItems,
} from './WeekTimeline.logic';
import {
  computeWeekTimelineSlots,
  type WeekTimelineSlotAssignment,
  type WeekTimelineSlotItem,
} from '../calendar/week-timeline/weekTimelineLayout';
import { TASK_STATUS } from '@lorvex/shared/types';

interface Props {
  weekDates: string[];
  tasksByDate: Record<string, Task[]>;
  eventsByDate: Record<string, UnifiedCalendarEvent[]>;
  today: string;
  locale: string;
  t: (key: TranslationKey) => string;
  onSelectTask?: ((taskId: string) => void) | undefined;
}

export default function WeekTimeline({
  weekDates,
  tasksByDate,
  eventsByDate,
  today,
  locale,
  t,
  onSelectTask,
}: Props) {
  const dayContext = useConfiguredDayContext();
  const nowHHMM = useCurrentTime(dayContext.timezone);
  const scrollRef = useRef<HTMLDivElement>(null);
  const lastInitialScrollSignatureRef = useRef<string | null>(null);
  const scrollAnchorItems = useMemo(
    () => weekTimelineScrollAnchorItems({ weekDates, tasksByDate, eventsByDate }),
    [eventsByDate, tasksByDate, weekDates],
  );
  const initialScrollSignature = useMemo(
    () => scrollAnchorItems.map((item) => `${item.id}:${item.startTime ?? ''}`).join('|'),
    [scrollAnchorItems],
  );

  // Auto-scroll to the week's first real timed item; if the week is empty, fall back to now.
  useEffect(() => {
    if (!scrollRef.current) return;
    if (lastInitialScrollSignatureRef.current === initialScrollSignature) return;
    lastInitialScrollSignatureRef.current = initialScrollSignature;
    const nowMin = parseTimeToMinutes(nowHHMM);
    scrollRef.current.scrollTop = weekTimelineInitialScrollTopForItems({
      currentMinutes: nowMin,
      timedItems: scrollAnchorItems,
    });
  }, [initialScrollSignature, nowHHMM, scrollAnchorItems]);

  const hours = useMemo(() => {
    return Array.from({ length: WEEK_TIMELINE_HOUR_COUNT }, (_, i) => {
      const h = WEEK_TIMELINE_HOUR_START + i;
      return `${String(h).padStart(2, '0')}:00`;
    });
  }, []);

  const columns = useMemo(() => {
    return weekDates.map((dateStr) => {
      const dayTasks = tasksByDate[dateStr] ?? [];
      const dayEvents = eventsByDate[dateStr] ?? [];

      const allDayEvents = dayEvents.filter((e) => e.all_day);
      const timedEvents = dayEvents.filter((e) => !e.all_day && e.start_time);

      const untimedTasks: Task[] = [];
      const timedTasks: PositionedTask[] = [];
      const completedTasks = dayTasks.filter((tk) => tk.status === TASK_STATUS.completed);

      for (const task of dayTasks) {
        if (task.status === TASK_STATUS.completed) continue;
        if (!task.due_time) {
          untimedTasks.push(task);
          continue;
        }
        const minutes = parseTimeToMinutes(task.due_time);
        if (minutes == null) {
          untimedTasks.push(task);
          continue;
        }
        const duration = task.estimated_minutes ?? 30;
        timedTasks.push({
          task,
          top: weekTimelineMinutesToOffset(minutes),
          height: weekTimelineDurationToHeight(duration),
        });
      }

      const positionedEvents: PositionedEvent[] = [];
      for (const event of timedEvents) {
        const geometry = weekTimelineEventGeometry(event.start_time, event.end_time);
        if (!geometry) continue;
        positionedEvents.push({
          event,
          top: geometry.top,
          height: geometry.height,
        });
      }

      // Pack overlapping timed chips into side-by-side columns. Events and
      // tasks share one lane assignment (keyed by prefixed id) so a meeting
      // and a same-slot task sit beside each other rather than stacking.
      const slotItems: WeekTimelineSlotItem[] = [
        ...positionedEvents.map(({ event }) => ({
          id: `evt:${event.id}`,
          start: event.start_time,
          end: event.end_time,
          fallbackDurationMinutes: WEEK_TIMELINE_DEFAULT_EVENT_DURATION,
        })),
        ...timedTasks.map(({ task }) => ({
          id: `task:${task.id}`,
          start: task.due_time,
          end: null,
          fallbackDurationMinutes: task.estimated_minutes ?? 30,
        })),
      ];
      const slots = computeWeekTimelineSlots(slotItems);

      return {
        dateStr,
        allDayEvents,
        positionedTasks: timedTasks,
        positionedEvents,
        slots,
        untimedTasks,
        completedCount: completedTasks.length,
      };
    });
  }, [weekDates, tasksByDate, eventsByDate]);

  const hasAllDay = columns.some((col) => col.allDayEvents.length > 0);
  const hasUntimed = columns.some((col) => col.untimedTasks.length > 0);
  const gridHeight = WEEK_TIMELINE_HOUR_COUNT * WEEK_TIMELINE_ROW_HEIGHT;

  return (
    <div className="h-full min-h-0 max-w-full overflow-x-auto overscroll-x-contain">
      <div className="flex h-full min-h-0 min-w-[52rem] flex-col">
        {/* Day headers */}
        <div className="flex shrink-0 border-b border-surface-3">
          <div className="w-12 shrink-0" />
          {columns.map(({ dateStr }) => {
            const { label, dayNum } = formatWeekTimelineDayLabel(dateStr, today, locale, t);
            const isToday = dateStr === today;
            const isPast = dateStr < today;
            return (
              <div
                key={dateStr}
                className="flex-1 min-w-0 text-center py-2 border-s border-surface-3"
              >
                <p className="text-xs font-medium text-text-muted">{label}</p>
                <div
                  className={`mx-auto mt-0.5 w-7 h-7 rounded-full flex items-center justify-center text-sm font-medium ${
                    isToday ? 'bg-accent text-on-accent active:scale-[0.97]' : isPast ? 'text-text-muted' : 'text-text-primary'
                  }`}
                >
                  {dayNum}
                </div>
              </div>
            );
          })}
        </div>

        {/* All-day events row */}
        {hasAllDay && (
          <div className="flex shrink-0 border-b border-surface-3">
            <div className="w-12 shrink-0 flex items-center justify-end pe-2">
              <span className="text-xs text-text-muted">{t('upcoming.allDay')}</span>
            </div>
            {columns.map(({ dateStr, allDayEvents }) => (
              <div key={dateStr} className="flex-1 min-w-0 border-s border-surface-3 px-0.5 py-1 space-y-0.5">
                {allDayEvents.map((event) => (
                  <div
                    key={event.id}
                    className="rounded-r-control px-1.5 py-0.5 text-2xs leading-tight truncate text-text-primary"
                    style={eventColorStyles(event.color ?? null, 'soft', 2)}
                  >
                    {eventTypeIcon(event.event_type)}{event.title}
                  </div>
                ))}
              </div>
            ))}
          </div>
        )}

        {/* Untimed tasks row */}
        {hasUntimed && (
          <div className="flex shrink-0 border-b border-surface-3">
            <div className="w-12 shrink-0 flex items-center justify-end pe-2">
              <span className="text-xs text-text-muted">{t('upcoming.noTime')}</span>
            </div>
            {columns.map(({ dateStr, untimedTasks }) => (
              <div key={dateStr} className="flex-1 min-w-0 border-s border-surface-3 px-0.5 py-1 space-y-0.5">
                {untimedTasks.slice(0, 4).map((task) => (
                  <UntimedTaskChip
                    key={task.id}
                    task={task}
                    dayContext={dayContext}
                    onClick={() => onSelectTask?.(task.id)}
                  />
                ))}
                {untimedTasks.length > 4 && (
                  <span className="text-2xs text-text-muted px-1">+{untimedTasks.length - 4}</span>
                )}
              </div>
            ))}
          </div>
        )}

        {/* Time grid */}
        <div ref={scrollRef} className="flex-1 overflow-y-auto overscroll-contain">
          <div className="flex" style={{ height: gridHeight }}>
            {/* Hour labels */}
            <div className="w-12 shrink-0 relative">
              {hours.map((label, i) => (
                <div
                  key={label}
                  className="absolute end-2 text-2xs text-text-muted font-mono -translate-y-1/2"
                  style={{ top: i * WEEK_TIMELINE_ROW_HEIGHT }}
                >
                  {label}
                </div>
              ))}
            </div>

            {/* Day columns */}
            {columns.map(({ dateStr, positionedTasks, positionedEvents, slots, completedCount }) => (
              <div key={dateStr} className="flex-1 min-w-0 relative border-s border-surface-3">
                {/* Hour grid lines */}
                {hours.map((_, i) => (
                  <div
                    key={i}
                    className="absolute start-0 end-0 border-t border-card"
                    style={{ top: i * WEEK_TIMELINE_ROW_HEIGHT }}
                  />
                ))}

                {/* Calendar events */}
                {positionedEvents.map(({ event, top, height }) => (
                  <TimelineEvent key={event.id} event={event} top={top} height={height} lane={slots.get(`evt:${event.id}`)} />
                ))}

                {/* Tasks */}
                {positionedTasks.map(({ task, top, height }) => (
                  <TimelineTask
                    key={task.id}
                    task={task}
                    top={top}
                    height={height}
                    lane={slots.get(`task:${task.id}`)}
                    dayContext={dayContext}
                    onClick={() => onSelectTask?.(task.id)}
                  />
                ))}

                {/* Current time indicator (today only) */}
                {dateStr === today && (() => {
                  const nowMin = parseTimeToMinutes(nowHHMM);
                  if (nowMin == null) return null;
                  if (
                    nowMin < WEEK_TIMELINE_HOUR_START * 60
                    || nowMin > WEEK_TIMELINE_HOUR_END * 60
                  ) return null;
                  const nowTop = weekTimelineMinutesToOffset(nowMin);
                  return (
                    <div
                      className="absolute start-0 end-0 flex items-center pointer-events-none z-[calc(var(--z-popover)-1)]"
                      style={{ top: nowTop }}
                    >
                      <div className="w-1.5 h-1.5 rounded-full bg-danger shrink-0 -ms-0.5" />
                      <div className="flex-1 h-px bg-[var(--danger-tint-xl)]" />
                    </div>
                  );
                })()}

                {/* Completed count badge */}
                {completedCount > 0 && (
                  <div
                    className="absolute bottom-1 end-1 text-2xs chip-success rounded-full px-1.5 py-0.5"
                  >
                    {'\u2713'} {completedCount}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function TimelineEvent({ event, top, height, lane }: { event: UnifiedCalendarEvent; top: number; height: number; lane: WeekTimelineSlotAssignment | undefined }) {
  const laneStyle = weekTimelineLaneStyle(lane);
  return (
    <div
      className="absolute rounded-r-control px-1.5 py-0.5 text-2xs leading-tight overflow-hidden cursor-default z-[var(--z-sticky)] text-text-primary"
      style={{
        top,
        height,
        insetInlineStart: laneStyle.insetInlineStart,
        width: laneStyle.width,
        // medium tier (~15% alpha) is closer to the original 25% than
        // soft (10%); the timeline event uses a slightly emphasized
        // wash to stand out against the gridlines.
        ...eventColorStyles(event.color ?? null, 'medium', 2),
      }}
    >
      <div className="font-medium truncate">{eventTypeIcon(event.event_type)}{event.title}</div>
      {height > 28 && event.start_time && (
        <div className="opacity-70 font-mono">
          {event.start_time}{event.end_time ? ` – ${event.end_time}` : ''}
        </div>
      )}
      {height > 42 && event.location && (
        <div className="opacity-60 truncate">{event.location}</div>
      )}
    </div>
  );
}

function TimelineTask({
  task,
  top,
  height,
  lane,
  dayContext,
  onClick,
}: {
  task: Task;
  top: number;
  height: number;
  lane: WeekTimelineSlotAssignment | undefined;
  dayContext: ReturnType<typeof useConfiguredDayContext>;
  onClick: () => void;
}) {
  const { t } = useI18n();
  const isOverdue = isDueOverdue(task.due_date, dayContext);
  const laneStyle = weekTimelineLaneStyle(lane);

  return (
    <button
      type="button"
      className={`absolute rounded-r-control px-1.5 py-0.5 text-2xs leading-tight overflow-hidden cursor-pointer transition-opacity hover:opacity-90 z-[calc(var(--z-popover)-1)] text-start focus-ring-soft ${
        isOverdue
          ? 'chip-danger border-s-2 border-danger'
          : 'bg-accent/10 text-accent border-s-2 border-accent'
      }`}
      style={{ top, height, insetInlineStart: laneStyle.insetInlineStart, width: laneStyle.width }}
      onClick={onClick}
      aria-label={task.title}
    >
      <div className="font-medium truncate">
        {task.recurrence ? '\u21BB ' : ''}
        {task.title}
      </div>
      {height > 28 && task.due_time && (
        <div className="opacity-70 font-mono">
          {task.due_time}
          {task.estimated_minutes ? ` (${task.estimated_minutes}${t('common.min')})` : ''}
        </div>
      )}
    </button>
  );
}

function UntimedTaskChip({
  task,
  dayContext,
  onClick,
}: {
  task: Task;
  dayContext: ReturnType<typeof useConfiguredDayContext>;
  onClick: () => void;
}) {
  const isOverdue = isDueOverdue(task.due_date, dayContext);

  return (
    <button
      type="button"
      className={`w-full rounded-r-control px-1 py-0.5 text-2xs leading-tight truncate cursor-pointer transition-opacity hover:opacity-80 text-start focus-ring-soft ${
        isOverdue ? 'chip-danger' : 'bg-accent/10 text-accent'
      }`}
      onClick={onClick}
      aria-label={task.title}
    >
      {task.recurrence ? '\u21BB ' : ''}
      {task.title}
    </button>
  );
}
