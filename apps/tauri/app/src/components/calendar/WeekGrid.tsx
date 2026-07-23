import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { WeekTimelineGrid } from './week-timeline/WeekTimelineGrid';
import type { WeekGridTaskReschedule } from './weekGridTypes';

interface WeekGridProps {
  weekStart: string;
  today: string;
  selectedDate: string | null;
  tasksByDate: Record<string, Task[]>;
  eventsByDate: Record<string, UnifiedCalendarEvent[]>;
  weekdayLabels: string[];
  /** Raw app locale; resolved+memoized inside `formatCalendarDate`. */
  locale: string;
  t: (key: TranslationKey) => string;
  onSelectDate: (date: string) => void;
  onSelectTask: (id: string) => void;
  onInvalidate: () => void;
  onRescheduleTask?: WeekGridTaskReschedule;
}

/**
 * Thin proxy that adapts the calendar-view controller's prop shape to
 * the full-week timeline component. Kept as a
 * separate file so call sites in `CalendarViewContent` and tests don't
 * have to update their import paths — the renderer is
 * `week-timeline/WeekTimelineGrid`.
 */
export function WeekGrid(props: WeekGridProps) {
  return <WeekTimelineGrid {...props} />;
}
