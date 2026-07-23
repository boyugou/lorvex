import { formatCalendarDate } from '../dates/dateLocale';
import type { DayContext } from '../dayContext';
import { addYmdDays, diffYmdDays } from '../dayContextMath';
import type { Task, TaskLateness } from '@lorvex/shared/types';
import { TASK_STATUS } from '@lorvex/shared/types';

/** Check if a task is in an actionable state (open or someday). */
export function isTaskActive(status: string): boolean {
  return status === TASK_STATUS.open || status === TASK_STATUS.someday;
}

export function parseTags(tags: string[] | null): string[] {
  return tags ?? [];
}


interface DueDateFormatOptions {
  dayContext: DayContext;
  locale?: string;
  todayLabel?: string;
  tomorrowLabel?: string;
  yesterdayLabel?: string;
}

function computeYesterdayYmd(todayYmd: string): string {
  return addYmdDays(todayYmd, -1);
}

export function formatDueDate(dueDate: string | null, options: DueDateFormatOptions): string {
  if (!dueDate) return '';
  const today = options.dayContext.todayYmd;
  const tomorrow = options.dayContext.tomorrowYmd;
  const locale = options.locale ?? 'en-US';
  const todayLabel = options.todayLabel ?? 'Today';
  const tomorrowLabel = options.tomorrowLabel ?? 'Tomorrow';
  const yesterdayLabel = options.yesterdayLabel ?? 'Yesterday';
  if (dueDate === today) return todayLabel;
  if (dueDate === tomorrow) return tomorrowLabel;
  if (dueDate === computeYesterdayYmd(today)) return yesterdayLabel;
  // For dates 2-6 days from now, show short weekday name (e.g. "Thu");
  // otherwise short month + day. Both calls share the memoized
  // formatter cache via `formatCalendarDate`.
  const diffDays = diffYmdDays(today, dueDate);
  if (diffDays >= 2 && diffDays <= 6) {
    return formatCalendarDate(dueDate, locale, { weekday: 'short' });
  }
  return formatCalendarDate(dueDate, locale, { month: 'short', day: 'numeric' });
}

export function isDueOverdue(dueDate: string | null, dayContext: DayContext): boolean {
  if (!dueDate) return false;
  return dueDate < dayContext.todayYmd;
}

const OVERDUE_LATENESS_STATES = new Set<TaskLateness>([
  'overdue_unhandled',
  'overdue_acknowledged',
]);

export function isTaskOverdue(
  task: Pick<Task, 'lateness_state' | 'due_date'>,
  dayContext: DayContext,
): boolean {
  if (task.lateness_state) return OVERDUE_LATENESS_STATES.has(task.lateness_state);
  return isDueOverdue(task.due_date, dayContext);
}


export function isDueToday(dueDate: string | null, dayContext: DayContext): boolean {
  if (!dueDate) return false;
  return dueDate === dayContext.todayYmd;
}
