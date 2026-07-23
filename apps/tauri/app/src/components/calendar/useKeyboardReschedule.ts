import type { KeyboardEvent } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { addDays } from './calendarViewUtils';

/**
 * Shared keyboard-reschedule handler for calendar task pills.
 *
 * Exists so MonthGrid (desktop), MobileWeekGrid, and WeekGrid all wire
 * the same key bindings without drifting. Keeps in sync with the
 * earlier Shift+Arrow precedent introduced on WeekGrid.WeekTask.
 *
 * Bindings:
 *   - Shift+ArrowLeft  / Shift+ArrowRight : shift the task -1 / +1 day.
 *   - ArrowLeft        / ArrowRight       : same as Shift form, so
 *                                           keyboard users who reach a
 *                                           pill via Tab can reschedule
 *                                           without a modifier — the
 *                                           pill is already focused and
 *                                           cells no longer compete for
 *                                           the arrow keys.
 *
 * Enter / Space open the task — handled by the surrounding <button>'s
 * default activation, so this hook deliberately doesn't consume them.
 *
 * The caller is responsible for deciding whether to attach the handler
 * (omit when onRescheduleTask is undefined or when the view is a read-
 * only context).
 */
export function useKeyboardReschedule(
  task: Task,
  onRescheduleTask:
    | ((taskId: string, newDate: string, oldDate: string | null, hasPlannedDate?: boolean) => void)
    | undefined,
): (event: KeyboardEvent) => void {
  return (event: KeyboardEvent) => {
    if (!onRescheduleTask) return;
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    const effectiveDate = task.planned_date ?? task.due_date;
    if (!effectiveDate) return;
    event.preventDefault();
    event.stopPropagation();
    const delta = event.key === 'ArrowLeft' ? -1 : 1;
    const newDate = addDays(effectiveDate, delta);
    onRescheduleTask(task.id, newDate, effectiveDate, !!task.planned_date);
  };
}
