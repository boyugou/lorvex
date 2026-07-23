import type { Task } from '@/lib/ipc/tasks/models';
import { classifyTaskRelativeSection } from '@/lib/tasks/dayBuckets';
// Comparator re-exports removed — import directly from `lib/tasks/taskComparators`.

export function rankFallbackFocusTask(task: Task, todayIso: string): number {
  switch (classifyTaskRelativeSection(task, todayIso)) {
    case 'overdue':
      return 0;
    case 'today':
      return 1;
    case 'tomorrow':
      return 2;
    case 'this_week':
      return 3;
    case 'no_date':
      return 4;
    case 'later':
    default:
      return 5;
  }
}

export function moveTaskId(order: string[], fromId: string, toId: string): string[] {
  const from = order.indexOf(fromId);
  const to = order.indexOf(toId);
  if (from < 0 || to < 0 || from === to) return order;
  const next = [...order];
  const [moved] = next.splice(from, 1);
  next.splice(to, 0, moved!);
  return next;
}
