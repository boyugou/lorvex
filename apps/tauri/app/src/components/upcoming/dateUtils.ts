import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { addYmdDays } from '@/lib/dayContextMath';

export function computeDateRange(todayYmd: string): { from: string; to: string } {
  return { from: todayYmd, to: addYmdDays(todayYmd, 6) };
}

export function computeWeekDates(todayYmd: string): string[] {
  return Array.from({ length: 7 }, (_, i) => addYmdDays(todayYmd, i));
}

export function sortEvents(events: UnifiedCalendarEvent[]): UnifiedCalendarEvent[] {
  return [...events].sort((left, right) => {
    if (left.all_day && !right.all_day) return -1;
    if (!left.all_day && right.all_day) return 1;
    if (left.start_time && right.start_time) {
      const cmp = left.start_time.localeCompare(right.start_time);
      if (cmp !== 0) return cmp;
    }
    return left.title.localeCompare(right.title);
  });
}
