import type { Task } from '@/lib/ipc/tasks/models';
import { addYmdDays } from '../dayContextMath';

type RelativeTaskSection = 'overdue' | 'today' | 'tomorrow' | 'this_week' | 'later' | 'no_date';

export function taskEffectiveActionDate(task: Pick<Task, 'planned_date' | 'due_date'>): string | null {
  return task.planned_date ?? task.due_date ?? null;
}

function isTaskDeadlineOverdue(task: Pick<Task, 'lateness_state' | 'due_date'>, todayYmd: string): boolean {
  if (task.lateness_state === 'overdue_unhandled' || task.lateness_state === 'overdue_acknowledged') {
    return true;
  }
  return task.due_date != null && task.due_date < todayYmd;
}

export function classifyTaskRelativeSection(
  task: Pick<Task, 'planned_date' | 'due_date' | 'lateness_state'>,
  todayYmd: string,
): RelativeTaskSection {
  if (isTaskDeadlineOverdue(task, todayYmd)) return 'overdue';

  const actionDate = taskEffectiveActionDate(task);
  if (!actionDate) return 'no_date';
  if (actionDate <= todayYmd) return 'today';

  const tomorrowYmd = addYmdDays(todayYmd, 1);
  if (actionDate === tomorrowYmd) return 'tomorrow';

  const endOfWeekYmd = addYmdDays(todayYmd, 7);
  if (actionDate <= endOfWeekYmd) return 'this_week';
  return 'later';
}

export function isTaskInRelativeSections(
  task: Pick<Task, 'planned_date' | 'due_date' | 'lateness_state'>,
  todayYmd: string,
  sections: readonly RelativeTaskSection[],
): boolean {
  return sections.includes(classifyTaskRelativeSection(task, todayYmd));
}
