import { parseTimeToMinutes } from '@/lib/timeUtils';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import { TASK_STATUS } from '@lorvex/shared/types';
import {
  TIMELINE_HOUR_COUNT,
  TIMELINE_HOUR_END,
  TIMELINE_HOUR_START,
  TIMELINE_ROW_HEIGHT,
  TIMELINE_SNAP_MINUTES,
  timelineDurationToHeight,
  timelineInitialScrollTop,
  timelineMinutesToTimeString,
  timelineMinutesToTop,
  timelineSnapMinutes,
  timelineTopToMinutes,
} from '../timelineLayout';

export const WEEK_TIMELINE_HOUR_START = TIMELINE_HOUR_START;

export const WEEK_TIMELINE_HOUR_END = TIMELINE_HOUR_END;

export const WEEK_TIMELINE_HOUR_COUNT = TIMELINE_HOUR_COUNT;

export const WEEK_TIMELINE_ROW_HEIGHT = TIMELINE_ROW_HEIGHT;

export const WEEK_TIMELINE_SNAP_MINUTES = TIMELINE_SNAP_MINUTES;

/** Fixed pixel width of the leftmost hour-label column. */
export const WEEK_TIMELINE_TIME_AXIS_WIDTH = 56;

/**
 * Minimum readable width for a single day column. Below this, timed
 * chips become impossible to scan, so the week surface scrolls
 * horizontally instead of compressing seven days into the viewport.
 */
export const WEEK_TIMELINE_DAY_MIN_WIDTH = 112;

/** Minimum width for the full week timeline including the time axis. */
export const WEEK_TIMELINE_MIN_WIDTH =
  WEEK_TIMELINE_TIME_AXIS_WIDTH + WEEK_TIMELINE_DAY_MIN_WIDTH * 7;

/** Minimum chip height so a 15-minute event stays clickable. */
const WEEK_TIMELINE_MIN_BLOCK_HEIGHT = 20;

/** Default duration (in minutes) when an event omits an end time. */
export const WEEK_TIMELINE_DEFAULT_EVENT_DURATION = 30;

/** Default duration (in minutes) for a task pinned at a specific due-time. */
export const WEEK_TIMELINE_DEFAULT_TASK_DURATION = 25;

/**
 * Total vertical pixels needed for one day's events. The grid container
 * uses this as its `height` so absolute positioning lands at the right
 * Y coordinate.
 */
export const WEEK_TIMELINE_TOTAL_HEIGHT =
  WEEK_TIMELINE_HOUR_COUNT * WEEK_TIMELINE_ROW_HEIGHT;

/**
 * Convert a wall-clock "HH:MM" minute count into a Y offset in pixels,
 * measured from the top of the timeline body. Full-day rendering keeps
 * early-morning travel, flights, and late-night events in their real
 * slots instead of compressing them into the top edge.
 */
export function weekTimelineMinutesToTop(minutes: number): number {
  return timelineMinutesToTop(minutes);
}

/**
 * Invert {@link weekTimelineMinutesToTop}: a Y offset (pixels from the top
 * of the timeline body, including scroll) back to wall-clock minutes. The
 * week body and the day timeline share `timelineLayout`'s geometry, so a
 * drop's Y maps to the same minute the chip at that Y would render at.
 */
export function weekTimelineTopToMinutes(top: number): number {
  return timelineTopToMinutes(top);
}

/** Snap a minute count to the timeline's 15-minute grid. */
export function weekTimelineSnapMinutes(minutes: number): number {
  return timelineSnapMinutes(minutes);
}

/** Format a minute count as a wire "HH:MM" string. */
export function weekTimelineMinutesToTimeString(minutes: number): string {
  return timelineMinutesToTimeString(minutes);
}

/** Convert a duration (minutes) into a chip height in pixels. */
function weekTimelineDurationToHeight(durationMinutes: number): number {
  return timelineDurationToHeight(durationMinutes, WEEK_TIMELINE_MIN_BLOCK_HEIGHT);
}

/**
 * Parse a wire-form HH:MM string and return its top-pixel + height
 * relative to the timeline grid, OR `null` if the inputs cannot be
 * parsed. Centralises the "compute geometry for a chip" recipe so the
 * event-chip and task-chip components share one source of truth.
 */
export function weekTimelineGeometry(
  startHHMM: string | null | undefined,
  endHHMM: string | null | undefined,
  fallbackDurationMinutes: number,
): { top: number; height: number } | null {
  if (!startHHMM) return null;
  const startMin = parseTimeToMinutes(startHHMM);
  if (startMin === null) return null;
  const endMin = endHHMM ? parseTimeToMinutes(endHHMM) : null;
  const duration =
    endMin !== null && endMin > startMin
      ? endMin - startMin
      : fallbackDurationMinutes;
  return {
    top: weekTimelineMinutesToTop(startMin),
    height: weekTimelineDurationToHeight(duration),
  };
}

export function weekTimelineInitialScrollTop({
  currentMinutes,
  selectedDayItems,
}: {
  currentMinutes: number;
  selectedDayItems: WeekTimelineSlotItem[];
}): number {
  return timelineInitialScrollTop({
    currentMinutes,
    timedItems: selectedDayItems.map((item) => ({ startTime: item.start })),
    emptyOffsetMinutes: 60,
  });
}

export interface WeekTimelineSlotItem {
  id: string;
  start: string | null | undefined;
  end: string | null | undefined;
  fallbackDurationMinutes: number;
}

function weekTimelineInitialScrollItems(
  events: UnifiedCalendarEvent[],
  tasks: Task[],
): WeekTimelineSlotItem[] {
  return [
    ...events
      .filter((event) => !event.all_day && event.start_time)
      .map((event) => ({
        id: event.id,
        start: event.start_time,
        end: event.end_time,
        fallbackDurationMinutes: WEEK_TIMELINE_DEFAULT_EVENT_DURATION,
      })),
    ...tasks
      .filter((task) => task.status === TASK_STATUS.open && task.due_time)
      .map((task) => ({
        id: task.id,
        start: task.due_time,
        end: null,
        fallbackDurationMinutes: task.estimated_minutes ?? WEEK_TIMELINE_DEFAULT_TASK_DURATION,
      })),
  ];
}

export function weekTimelineScrollAnchorItems({
  selectedDate,
  weekDates,
  eventsByDate,
  tasksByDate,
}: {
  selectedDate: string | null;
  weekDates: string[];
  eventsByDate: Record<string, UnifiedCalendarEvent[]>;
  tasksByDate: Record<string, Task[]>;
}): WeekTimelineSlotItem[] {
  if (selectedDate) {
    return weekTimelineInitialScrollItems(
      eventsByDate[selectedDate] ?? [],
      tasksByDate[selectedDate] ?? [],
    );
  }

  return weekDates.flatMap((date) =>
    weekTimelineInitialScrollItems(
      eventsByDate[date] ?? [],
      tasksByDate[date] ?? [],
    ),
  );
}

export interface WeekTimelineSlotAssignment {
  index: number;
  count: number;
}

interface NormalizedWeekTimelineSlotItem {
  id: string;
  start: number;
  end: number;
}

export function computeWeekTimelineSlots(
  items: WeekTimelineSlotItem[],
): Map<string, WeekTimelineSlotAssignment> {
  const normalized = items
    .map(normalizeWeekTimelineSlotItem)
    .filter((item): item is NormalizedWeekTimelineSlotItem => item !== null)
    .sort((a, b) => {
      if (a.start !== b.start) return a.start - b.start;
      if (a.end !== b.end) return a.end - b.end;
      return a.id.localeCompare(b.id);
    });

  if (normalized.length === 0) return new Map();

  const result = new Map<string, WeekTimelineSlotAssignment>();
  let cluster: NormalizedWeekTimelineSlotItem[] = [];
  let clusterEnd = -Infinity;

  for (const item of normalized) {
    if (cluster.length > 0 && item.start >= clusterEnd) {
      assignWeekTimelineCluster(cluster, result);
      cluster = [];
      clusterEnd = -Infinity;
    }
    cluster.push(item);
    clusterEnd = Math.max(clusterEnd, item.end);
  }

  if (cluster.length > 0) {
    assignWeekTimelineCluster(cluster, result);
  }

  return result;
}

function normalizeWeekTimelineSlotItem(
  item: WeekTimelineSlotItem,
): NormalizedWeekTimelineSlotItem | null {
  if (!item.start) return null;
  const start = parseTimeToMinutes(item.start);
  if (start === null) return null;
  const parsedEnd = item.end ? parseTimeToMinutes(item.end) : null;
  const end =
    parsedEnd !== null && parsedEnd > start
      ? parsedEnd
      : start + Math.max(1, item.fallbackDurationMinutes);
  return { id: item.id, start, end };
}

function assignWeekTimelineCluster(
  items: NormalizedWeekTimelineSlotItem[],
  result: Map<string, WeekTimelineSlotAssignment>,
) {
  const columnEndMinutes: number[] = [];
  const clusterAssignments = new Map<string, number>();

  for (const item of items) {
    let columnIndex = columnEndMinutes.findIndex((end) => end <= item.start);
    if (columnIndex === -1) {
      columnIndex = columnEndMinutes.length;
      columnEndMinutes.push(item.end);
    } else {
      columnEndMinutes[columnIndex] = item.end;
    }
    clusterAssignments.set(item.id, columnIndex);
  }

  const count = Math.max(1, columnEndMinutes.length);
  for (const [id, index] of clusterAssignments) {
    result.set(id, { index, count });
  }
}
