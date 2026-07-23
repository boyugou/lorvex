export const WEEK_ALL_DAY_VISIBLE_ITEM_LIMIT = 3;

export interface WeekAllDayStripItem {
  id: string;
}

export interface WeekAllDayEventItem extends WeekAllDayStripItem {
  start_date: string;
  end_date?: string | null;
}

export interface WeekAllDayVisibleItems<T extends WeekAllDayStripItem> {
  visible: T[];
  hiddenCount: number;
}

export interface WeekAllDaySegment<T extends WeekAllDayEventItem> {
  key: string;
  item: T;
  startIndex: number;
  endIndex: number;
  lane: number;
}

export interface WeekAllDaySegments<T extends WeekAllDayEventItem> {
  visible: WeekAllDaySegment<T>[];
  hiddenByDate: Record<string, number>;
}

export interface WeekAllDaySegmentHitTarget<T extends WeekAllDayEventItem> {
  key: string;
  item: T;
  date: string;
  index: number;
  isStart: boolean;
  isEnd: boolean;
}

export function resolveWeekAllDayVisibleItems<T extends WeekAllDayStripItem>(
  items: T[],
  limit = WEEK_ALL_DAY_VISIBLE_ITEM_LIMIT,
): WeekAllDayVisibleItems<T> {
  const visibleLimit = Math.max(0, Math.floor(limit));
  return {
    visible: items.slice(0, visibleLimit),
    hiddenCount: Math.max(0, items.length - visibleLimit),
  };
}

export function resolveWeekAllDaySegments<T extends WeekAllDayEventItem>({
  weekDates,
  eventsByDate,
  limit = WEEK_ALL_DAY_VISIBLE_ITEM_LIMIT,
}: {
  weekDates: string[];
  eventsByDate: Record<string, T[]>;
  limit?: number;
}): WeekAllDaySegments<T> {
  const visibleLaneLimit = Math.max(0, Math.floor(limit));
  const uniqueEvents = uniqueAllDayEvents(weekDates, eventsByDate);
  const laneEnds: number[] = [];
  const visible: WeekAllDaySegment<T>[] = [];
  const hiddenByDate: Record<string, number> = {};

  for (const event of uniqueEvents) {
    const range = clampEventToWeek(event, weekDates);
    if (!range) continue;
    let lane = laneEnds.findIndex((endIndex) => endIndex < range.startIndex);
    if (lane === -1) {
      lane = laneEnds.length;
      laneEnds.push(range.endIndex);
    } else {
      laneEnds[lane] = range.endIndex;
    }

    if (lane < visibleLaneLimit) {
      visible.push({
        key: weekAllDayOccurrenceKey(event),
        item: event,
        startIndex: range.startIndex,
        endIndex: range.endIndex,
        lane,
      });
      continue;
    }

    for (let index = range.startIndex; index <= range.endIndex; index += 1) {
      const date = weekDates[index];
      if (!date) continue;
      hiddenByDate[date] = (hiddenByDate[date] ?? 0) + 1;
    }
  }

  return { visible, hiddenByDate };
}

export function weekAllDaySegmentHitTargets<T extends WeekAllDayEventItem>(
  segment: WeekAllDaySegment<T>,
  weekDates: string[],
): WeekAllDaySegmentHitTarget<T>[] {
  const targets: WeekAllDaySegmentHitTarget<T>[] = [];
  for (let index = segment.startIndex; index <= segment.endIndex; index += 1) {
    const date = weekDates[index];
    if (!date) continue;
    targets.push({
      key: `${segment.key}:${date}`,
      item: segment.item,
      date,
      index,
      isStart: index === segment.startIndex,
      isEnd: index === segment.endIndex,
    });
  }
  return targets;
}


function uniqueAllDayEvents<T extends WeekAllDayEventItem>(
  weekDates: string[],
  eventsByDate: Record<string, T[]>,
): T[] {
  const seen = new Set<string>();
  const events: T[] = [];
  for (const date of weekDates) {
    for (const event of eventsByDate[date] ?? []) {
      const key = weekAllDayOccurrenceKey(event);
      if (seen.has(key)) continue;
      seen.add(key);
      events.push(event);
    }
  }
  return events.sort((a, b) => {
    const aEnd = a.end_date || a.start_date;
    const bEnd = b.end_date || b.start_date;
    if (a.start_date !== b.start_date) return a.start_date.localeCompare(b.start_date);
    if (aEnd !== bEnd) return bEnd.localeCompare(aEnd);
    return a.id.localeCompare(b.id);
  });
}

function weekAllDayOccurrenceKey(event: WeekAllDayEventItem): string {
  return `${event.id}:${event.start_date}:${event.end_date || event.start_date}`;
}

function clampEventToWeek<T extends WeekAllDayEventItem>(
  event: T,
  weekDates: string[],
): { startIndex: number; endIndex: number } | null {
  const firstWeekDate = weekDates[0];
  const lastWeekDate = weekDates[weekDates.length - 1];
  if (!firstWeekDate || !lastWeekDate) return null;

  const rawStart = event.start_date;
  const rawEnd = event.end_date || event.start_date;
  if (rawEnd < firstWeekDate || rawStart > lastWeekDate) return null;

  const clampedStart = rawStart < firstWeekDate ? firstWeekDate : rawStart;
  const clampedEnd = rawEnd > lastWeekDate ? lastWeekDate : rawEnd;
  const startIndex = weekDates.indexOf(clampedStart);
  const endIndex = weekDates.indexOf(clampedEnd);
  if (startIndex === -1 || endIndex === -1 || endIndex < startIndex) return null;
  return { startIndex, endIndex };
}
