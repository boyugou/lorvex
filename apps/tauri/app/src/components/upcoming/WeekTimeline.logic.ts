import { formatCalendarDate } from '@/lib/dates/dateLocale';
import { addYmdDays } from '@/lib/dayContextMath';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { parseTimeToMinutes } from '@/lib/timeUtils';
import { TASK_STATUS } from '@lorvex/shared/types';
import {
  TIMELINE_HOUR_COUNT,
  TIMELINE_HOUR_END,
  TIMELINE_HOUR_START,
  TIMELINE_ROW_HEIGHT,
  timelineDurationToHeight,
  timelineInitialScrollTop,
  timelineMinutesToTop,
} from '../calendar/timelineLayout';

const CANONICAL_DAY_SEGMENT = /^\d{4}-\d{2}-(0[1-9]|[12]\d|3[01])$/;
export const WEEK_TIMELINE_HOUR_START = TIMELINE_HOUR_START;
export const WEEK_TIMELINE_HOUR_END = TIMELINE_HOUR_END;
export const WEEK_TIMELINE_HOUR_COUNT = TIMELINE_HOUR_COUNT;
export const WEEK_TIMELINE_ROW_HEIGHT = TIMELINE_ROW_HEIGHT;
const WEEK_TIMELINE_MIN_BLOCK_HEIGHT = 20;
export const WEEK_TIMELINE_DEFAULT_EVENT_DURATION = 60;

export function parseWeekTimelineDayNumberLabel(dateStr: string): string {
  if (!CANONICAL_DAY_SEGMENT.test(dateStr)) return '';
  return String(Number(dateStr.slice(8, 10)));
}

export function formatWeekTimelineDayLabel(
  dateStr: string,
  today: string,
  locale: string,
  t: (key: TranslationKey) => string,
): { label: string; dayNum: string } {
  const dayNum = parseWeekTimelineDayNumberLabel(dateStr);
  if (dateStr === today) return { label: t('upcoming.today'), dayNum };

  const tomorrowStr = addYmdDays(today, 1);
  if (dateStr === tomorrowStr) return { label: t('upcoming.tomorrow'), dayNum };

  const dayName = formatCalendarDate(dateStr, locale, { weekday: 'short' });
  return { label: dayName, dayNum };
}

export function weekTimelineMinutesToOffset(minutes: number): number {
  return timelineMinutesToTop(minutes);
}

export function weekTimelineDurationToHeight(estimatedMinutes: number): number {
  return timelineDurationToHeight(estimatedMinutes, WEEK_TIMELINE_MIN_BLOCK_HEIGHT);
}

export interface WeekTimelineTimedItem {
  id: string;
  startTime: string | null | undefined;
}

export function weekTimelineInitialScrollTopForItems({
  currentMinutes,
  timedItems,
}: {
  currentMinutes: number | null;
  timedItems: WeekTimelineTimedItem[];
}): number {
  return timelineInitialScrollTop({
    currentMinutes,
    timedItems,
    emptyOffsetMinutes: 60,
  });
}

export function weekTimelineScrollAnchorItems({
  weekDates,
  tasksByDate,
  eventsByDate,
}: {
  weekDates: string[];
  tasksByDate: Record<string, Task[]>;
  eventsByDate: Record<string, UnifiedCalendarEvent[]>;
}): WeekTimelineTimedItem[] {
  return weekDates.flatMap((dateStr) => {
    const events = eventsByDate[dateStr] ?? [];
    const tasks = tasksByDate[dateStr] ?? [];
    return [
      ...events
        .filter((event) => !event.all_day && event.start_time)
        .map((event) => ({ id: event.id, startTime: event.start_time })),
      ...tasks
        .filter((task) => task.status === TASK_STATUS.open && task.due_time)
        .map((task) => ({ id: task.id, startTime: task.due_time })),
    ];
  });
}

/**
 * Horizontal band geometry for a timed chip given its overlap slot.
 * Chips share the full day column (inset `0.125rem` each side, matching
 * the legacy `start-0.5 end-0.5` rule); concurrent chips split the band
 * into `count` equal columns and sit side by side in column `index`
 * instead of stacking and occluding each other. A lone chip (`count` 1,
 * or no slot) spans the full band exactly as before. Logical
 * `inset-inline-start` keeps the layout correct under RTL.
 */
export function weekTimelineLaneStyle(
  slot: { index: number; count: number } | undefined,
): { insetInlineStart: string; width: string } {
  const index = slot ? slot.index : 0;
  const count = slot && slot.count > 0 ? slot.count : 1;
  const gap = count > 1 ? 1 : 0;
  return {
    insetInlineStart: `calc(0.125rem + (100% - 0.25rem) * ${index} / ${count})`,
    width: `calc((100% - 0.25rem) / ${count} - ${gap}px)`,
  };
}

export function weekTimelineEventGeometry(
  startHHMM: string | null | undefined,
  endHHMM: string | null | undefined,
): { top: number; height: number } | null {
  if (!startHHMM) return null;
  const startMin = parseTimeToMinutes(startHHMM);
  if (startMin == null) return null;
  const endMin = endHHMM ? parseTimeToMinutes(endHHMM) : null;
  const duration =
    endMin !== null
      ? Math.max(endMin - startMin, 15)
      : WEEK_TIMELINE_DEFAULT_EVENT_DURATION;
  return {
    top: weekTimelineMinutesToOffset(startMin),
    height: weekTimelineDurationToHeight(duration),
  };
}
