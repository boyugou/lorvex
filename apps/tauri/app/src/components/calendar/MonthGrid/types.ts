import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';

/**
 * Shared props for the MonthGrid entry point and both branch
 * implementations. Extracted during the M29 split so the desktop
 * and mobile renderers can be typed consistently from a single
 * declaration.
 */
export interface MonthGridProps {
  year: number;
  month: number;
  today: string;
  selectedDate: string | null;
  tasksByDate: Record<string, Task[]>;
  eventsByDate: Record<string, UnifiedCalendarEvent[]>;
  weekdayLabels: string[];
  weekStartDay?: number;
  /**
   * Raw app locale (e.g. `"en"`, `"zh"`). The MonthGrid tree formats
   * via `lib/dateLocale::formatDate` / `formatCalendarDate`, both of
   * which resolve the locale internally and route through the shared
   * memoized formatter cache. Passing the raw locale (rather than a
   * pre-resolved formatter token) keeps a single source of truth at
   * the caller boundary at no cost given memoization.
   */
  locale: string;
  t: (key: TranslationKey) => string;
  onSelectDate: (date: string) => void;
  onSelectTask?: ((taskId: string) => void) | undefined;
  onRescheduleTask?:
    | ((taskId: string, newDate: string, oldDate: string | null, hasPlannedDate?: boolean) => void)
    | undefined;
}

/**
 * Per-cell precomputed classification used by the desktop branch.
 * Materialized once per (tasksByDate, eventsByDate, maxItems, dayContext)
 * tuple so cell renders are O(1) lookups during a drag sweep.
 */
export interface CellClassification {
  hasOverdue: boolean;
  openTasks: Task[];
  completedTasks: Task[];
  shownEvents: UnifiedCalendarEvent[];
  shownTasks: Task[];
  totalHidden: number;
}
