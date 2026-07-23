import { eventColorStyles } from '@/lib/colorUtils';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { TASK_STATUS } from '@lorvex/shared/types';
import { eventTypeIcon } from '../eventTypeIcon';
import {
  resolveWeekAllDaySegments,
  resolveWeekAllDayVisibleItems,
  weekAllDaySegmentHitTargets,
} from './WeekAllDayStrip.logic';
import { WEEK_TIMELINE_TIME_AXIS_WIDTH } from './weekTimelineLayout';

interface WeekAllDayStripProps {
  /** Same 7-day order the rest of the grid uses. */
  weekDays: { dateStr: string; isWeekend: boolean; isToday: boolean }[];
  eventsByDate: Record<string, UnifiedCalendarEvent[]>;
  tasksByDate: Record<string, Task[]>;
  untitledEventLabel: string;
  t: (key: TranslationKey) => string;
  onSelectTask: (id: string) => void;
  onSelectDate: (date: string) => void;
}

/**
 * Top strip above the timeline body that hosts items the time grid
 * cannot anchor:
 *
 *  - calendar events with `all_day === true`
 *  - tasks with a `due_date` but no `due_time`
 *
 * Multi-day all-day events render as continuous bars spanning the
 * affected day columns; untimed tasks stay day-local below those bars.
 * The leading `WEEK_TIMELINE_TIME_AXIS_WIDTH` spacer keeps the chips
 * aligned with the day columns below.
 */
export function WeekAllDayStrip({
  weekDays,
  eventsByDate,
  tasksByDate,
  untitledEventLabel,
  t,
  onSelectTask,
  onSelectDate,
}: WeekAllDayStripProps) {
  // Compute the rows up front so we can skip the strip entirely when
  // the whole week has nothing to show. Avoids a 1px hairline that
  // would otherwise sit between the day headers and the grid for
  // weeks with no all-day content.
  const allDayEventsByDate = Object.fromEntries(
    weekDays.map(({ dateStr }) => [
      dateStr,
      (eventsByDate[dateStr] ?? []).filter((event) => event.all_day),
    ]),
  );
  const allDaySegments = resolveWeekAllDaySegments({
    weekDates: weekDays.map((day) => day.dateStr),
    eventsByDate: allDayEventsByDate,
  });
  const weekDates = weekDays.map((day) => day.dateStr);
  const rows = weekDays.map(({ dateStr }) => {
    const untimed = (tasksByDate[dateStr] ?? []).filter(
      (task) => task.status === TASK_STATUS.open && !task.due_time,
    );
    return { untimed };
  });
  const visibleAllDayLaneCount = allDaySegments.visible.reduce(
    (max, segment) => Math.max(max, segment.lane + 1),
    0,
  );
  const anyItems =
    rows.some((row) => row.untimed.length > 0)
    || allDaySegments.visible.length > 0
    || Object.keys(allDaySegments.hiddenByDate).length > 0;
  if (!anyItems) return null;

  return (
    <div className="shrink-0 flex border-b border-surface-3 bg-surface-1/30">
      {/* Spacer to align with the hour-label column below. */}
      <div
        aria-hidden="true"
        className="shrink-0 border-e border-surface-3"
        style={{ width: WEEK_TIMELINE_TIME_AXIS_WIDTH }}
      />
      <div
        className="grid flex-1 min-w-0"
        style={{ gridTemplateColumns: 'repeat(7, minmax(0, 1fr))' }}
      >
        <div
          aria-hidden="true"
          className="grid col-span-7 row-start-1 pointer-events-none"
          style={{
            gridTemplateColumns: 'repeat(7, minmax(0, 1fr))',
            gridRow: `1 / ${visibleAllDayLaneCount + 2}`,
          }}
        >
          {weekDays.map(({ dateStr, isWeekend, isToday }) => (
            <div
              key={dateStr}
              data-today={isToday || undefined}
              className={`min-h-full border-e border-surface-3 ${
                isWeekend ? 'bg-surface-1/40' : ''
              } data-[today]:bg-[var(--accent-tint-xxs)]`}
            />
          ))}
        </div>

        {visibleAllDayLaneCount > 0 && (
          <div
            className="grid col-span-7 row-start-1 gap-y-0.5 px-1 py-1"
            style={{
              gridTemplateColumns: 'repeat(7, minmax(0, 1fr))',
              gridTemplateRows: `repeat(${visibleAllDayLaneCount}, minmax(20px, auto))`,
            }}
          >
            {allDaySegments.visible.flatMap((segment) => {
              const { item: event, lane } = segment;
              const styles = eventColorStyles(event.color ?? null, 'soft');
              const eventTitle = event.title || untitledEventLabel;
              return weekAllDaySegmentHitTargets(segment, weekDates).map((target) => (
                <button
                  type="button"
                  key={target.key}
                  onClick={() => onSelectDate(target.date)}
                  className={`truncate px-1.5 py-0.5 text-2xs text-start hover:brightness-95 active:scale-[0.99] transition-[filter,transform] focus-ring-soft ${
                    target.isStart ? 'rounded-s-control' : ''
                  } ${target.isEnd ? 'rounded-e-control' : ''}`}
                  style={{
                    ...styles,
                    gridColumn: `${target.index + 1} / ${target.index + 2}`,
                    gridRow: lane + 1,
                  }}
                  title={event.title}
                  aria-label={`${eventTitle} — ${t('calendar.eventAllDay')}`}
                >
                  {target.isStart && eventTypeIcon(event.event_type)}
                  {target.isStart ? eventTitle : ''}
                </button>
              ));
            })}
          </div>
        )}

        {weekDays.map(({ dateStr }, index) => {
          const row = rows[index];
          if (!row) return null;
          const untimed = resolveWeekAllDayVisibleItems(row.untimed);
          const hiddenCount = (allDaySegments.hiddenByDate[dateStr] ?? 0) + untimed.hiddenCount;
          return (
            <div
              key={dateStr}
              className="min-w-0 border-e border-surface-3 px-1 pb-1 space-y-0.5"
              style={{ gridRow: visibleAllDayLaneCount + 1 }}
            >
              {untimed.visible.map((task) => (
                <button
                  key={task.id}
                  type="button"
                  onClick={() => onSelectTask(task.id)}
                  className="w-full truncate rounded-r-control border border-accent/25 bg-[var(--accent-tint-xs)] px-1.5 py-0.5 text-2xs text-start hover:bg-[var(--accent-tint-sm)] transition-colors focus-ring-soft"
                  title={task.title}
                >
                  <span aria-hidden="true" className="text-accent me-1">✓</span>
                  {task.title}
                  <span className="sr-only"> — {t('common.task')}</span>
                </button>
              ))}
              {hiddenCount > 0 && (
                <button
                  type="button"
                  onClick={() => onSelectDate(dateStr)}
                  className="w-full truncate rounded-r-control px-1.5 py-0.5 text-2xs text-start text-text-muted hover:bg-surface-2 transition-colors focus-ring-soft"
                  title={`+${hiddenCount} ${t('calendar.more')}`}
                >
                  +{hiddenCount} {t('calendar.more')}
                </button>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
