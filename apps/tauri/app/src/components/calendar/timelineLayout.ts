import { parseTimeToMinutes } from '@/lib/timeUtils';

export const TIMELINE_HOUR_START = 0;
export const TIMELINE_HOUR_END = 24;
export const TIMELINE_HOUR_COUNT = TIMELINE_HOUR_END - TIMELINE_HOUR_START;
export const TIMELINE_ROW_HEIGHT = 56;
export const TIMELINE_SNAP_MINUTES = 15;
const TIMELINE_EARLY_ANCHOR_THRESHOLD_MINUTES = 8 * 60;

interface TimelineInitialScrollItem {
  startTime: string | null | undefined;
}

interface TimelineInitialScrollInput {
  currentMinutes: number | null;
  timedItems: TimelineInitialScrollItem[];
  viewportHeight?: number | null | undefined;
  emptyOffsetMinutes?: number | null | undefined;
}

export function timelineMinutesToTop(minutes: number): number {
  const clamped = Math.max(
    TIMELINE_HOUR_START * 60,
    Math.min(minutes, TIMELINE_HOUR_END * 60),
  );
  return ((clamped - TIMELINE_HOUR_START * 60) / 60) * TIMELINE_ROW_HEIGHT;
}

export function timelineDurationToHeight(
  durationMinutes: number,
  minimumBlockHeight: number,
): number {
  return Math.max((durationMinutes / 60) * TIMELINE_ROW_HEIGHT, minimumBlockHeight);
}

export function timelineTopToMinutes(top: number): number {
  return (top / TIMELINE_ROW_HEIGHT) * 60 + TIMELINE_HOUR_START * 60;
}

export function timelineSnapMinutes(minutes: number): number {
  return Math.round(minutes / TIMELINE_SNAP_MINUTES) * TIMELINE_SNAP_MINUTES;
}

export function timelineMinutesToTimeString(minutes: number): string {
  const clamped = Math.max(0, Math.min(minutes, 23 * 60 + 59));
  const h = Math.floor(clamped / 60);
  const m = clamped % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

export function timelineInitialScrollTop({
  currentMinutes,
  timedItems,
  viewportHeight = null,
  emptyOffsetMinutes = null,
}: TimelineInitialScrollInput): number {
  const earliestTimedMinutes = timedItems.reduce<number | null>((earliest, item) => {
    if (!item.startTime) return earliest;
    const minutes = parseTimeToMinutes(item.startTime);
    if (minutes === null) return earliest;
    return earliest === null ? minutes : Math.min(earliest, minutes);
  }, null);

  if (earliestTimedMinutes !== null) {
    return timelineMinutesToTop(timelineAnchorMinutes(earliestTimedMinutes));
  }

  if (currentMinutes === null) return 0;
  if (currentMinutes < TIMELINE_HOUR_START * 60 || currentMinutes > TIMELINE_HOUR_END * 60) {
    return 0;
  }

  const offset =
    viewportHeight !== null && viewportHeight !== undefined
      ? viewportHeight / 3
      : (emptyOffsetMinutes ?? 0) / 60 * TIMELINE_ROW_HEIGHT;
  return Math.max(0, timelineMinutesToTop(currentMinutes) - offset);
}

function timelineAnchorMinutes(earliestTimedMinutes: number): number {
  if (earliestTimedMinutes < TIMELINE_EARLY_ANCHOR_THRESHOLD_MINUTES) {
    return TIMELINE_HOUR_START * 60;
  }
  return Math.max(TIMELINE_HOUR_START * 60, earliestTimedMinutes - 30);
}
