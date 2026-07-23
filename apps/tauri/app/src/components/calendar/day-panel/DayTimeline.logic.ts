import { tryParseJson } from '@/lib/security/jsonParse';
import { hasOnlyKeys, isPlainRecord as isRecord } from '@/lib/objectGuards';
import { parseTimeToMinutes } from '@/lib/timeUtils';
import {
  TIMELINE_HOUR_END,
  TIMELINE_HOUR_START,
  TIMELINE_ROW_HEIGHT,
  TIMELINE_SNAP_MINUTES,
  timelineInitialScrollTop,
  timelineMinutesToTimeString,
  timelineMinutesToTop,
} from '../timelineLayout';

export const DAY_TIMELINE_HOUR_START = TIMELINE_HOUR_START;
export const DAY_TIMELINE_HOUR_END = TIMELINE_HOUR_END;
export const DAY_TIMELINE_ROW_HEIGHT = TIMELINE_ROW_HEIGHT;
export const DAY_TIMELINE_SNAP_MINUTES = TIMELINE_SNAP_MINUTES;
export const DAY_TIMELINE_TASK_KEYSHORTCUTS =
  'Meta+Shift+ArrowUp Control+Shift+ArrowUp Meta+Shift+ArrowDown Control+Shift+ArrowDown';

interface DayTimelineDragPayload {
  taskId: string;
  oldTime: string | null;
}

interface DayTimelineKeyboardRescheduleInput {
  key: string;
  oldTime: string | null;
  shiftKey?: boolean | undefined;
  metaKey?: boolean | undefined;
  ctrlKey?: boolean | undefined;
  altKey?: boolean | undefined;
}

interface DayTimelineInitialScrollInput {
  nowHHMM?: string | null | undefined;
  viewportHeight: number;
  timedItems: { startTime: string | null | undefined }[];
}

const DAY_TIMELINE_DRAG_PAYLOAD_KEYS = new Set(['taskId', 'oldTime']);

function isCanonicalOldTime(value: unknown): value is string | null {
  if (value === null) return true;
  return typeof value === 'string' && parseTimeToMinutes(value) !== null;
}

export function parseDayTimelineDragPayload(raw: string): DayTimelineDragPayload | null {
  const parseResult = tryParseJson(raw);
  if (!parseResult.ok) return null;

  const parsed = parseResult.value;
  if (!isRecord(parsed)) return null;
  if (!hasOnlyKeys(parsed, DAY_TIMELINE_DRAG_PAYLOAD_KEYS)) {
    return null;
  }
  if (typeof parsed.taskId !== 'string' || parsed.taskId.trim() === '') return null;
  if (!isCanonicalOldTime(parsed.oldTime)) return null;
  return {
    taskId: parsed.taskId,
    oldTime: parsed.oldTime,
  };
}

export function serializeDayTimelineDragPayload(taskId: string, oldTime: string | null): string {
  return JSON.stringify({ taskId, oldTime });
}

export function resolveDayTimelineInitialScrollTop({
  nowHHMM,
  timedItems,
  viewportHeight,
}: DayTimelineInitialScrollInput): number {
  return timelineInitialScrollTop({
    currentMinutes: nowHHMM ? parseTimeToMinutes(nowHHMM) : null,
    timedItems,
    viewportHeight,
  });
}

export function resolveDayTimelineKeyboardReschedule({
  key,
  oldTime,
  shiftKey = false,
  metaKey = false,
  ctrlKey = false,
  altKey = false,
}: DayTimelineKeyboardRescheduleInput): string | null {
  if (key !== 'ArrowUp' && key !== 'ArrowDown') return null;
  if (!shiftKey || altKey || (!metaKey && !ctrlKey)) return null;

  const minMinutes = DAY_TIMELINE_HOUR_START * 60;
  const maxMinutes = DAY_TIMELINE_HOUR_END * 60 - DAY_TIMELINE_SNAP_MINUTES;
  const direction = key === 'ArrowUp' ? -1 : 1;
  if (oldTime == null) {
    return timelineMinutesToTimeString(direction > 0 ? minMinutes : maxMinutes);
  }

  const currentMinutes = parseTimeToMinutes(oldTime);
  if (currentMinutes == null) return null;
  const nextMinutes = Math.max(
    minMinutes,
    Math.min(currentMinutes + direction * DAY_TIMELINE_SNAP_MINUTES, maxMinutes),
  );
  if (nextMinutes === currentMinutes) return null;
  return timelineMinutesToTimeString(nextMinutes);
}

/**
 * New duration (minutes) for a timed chip whose bottom edge was dragged by
 * `deltaY` pixels. Converts the pixel delta to minutes at the timeline's
 * `rowHeight` (px per hour), snaps to `snapMinutes`, and floors at `minMinutes`
 * so a chip can't be resized below one snap step. Used by the day-timeline task
 * resize handle; pure so it is unit-tested without the DOM.
 */
export function dayTimelineResizedMinutes({
  startMinutes,
  deltaY,
  rowHeight,
  snapMinutes,
  minMinutes,
}: {
  startMinutes: number;
  deltaY: number;
  rowHeight: number;
  snapMinutes: number;
  minMinutes: number;
}): number {
  const deltaMinutes = (deltaY / rowHeight) * 60;
  const snapped = Math.round((startMinutes + deltaMinutes) / snapMinutes) * snapMinutes;
  return Math.max(minMinutes, snapped);
}

/**
 * Horizontal band geometry for a timed chip given its overlap slot.
 * Chips share the area between the hour-label gutter (`2.5rem`, matching
 * the `start-10` inset) and the right edge inset (`0.25rem`, matching
 * `end-1`); concurrent chips split that band into `count` equal columns
 * and sit side by side in column `index` instead of occluding each
 * other. A lone chip (`count` 1, or no slot) spans the full band exactly
 * as the legacy `start-10 end-1` rule did. Logical `inset-inline-start`
 * keeps the layout correct under RTL.
 */
export function dayTimelineLaneStyle(
  slot: { index: number; count: number } | undefined,
): { insetInlineStart: string; width: string } {
  const index = slot ? slot.index : 0;
  const count = slot && slot.count > 0 ? slot.count : 1;
  const gap = count > 1 ? 2 : 0;
  return {
    insetInlineStart: `calc(2.5rem + (100% - 2.75rem) * ${index} / ${count})`,
    width: `calc((100% - 2.75rem) / ${count} - ${gap}px)`,
  };
}

export { timelineMinutesToTop as dayTimelineMinutesToTop };
