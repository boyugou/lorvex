import { getListWithTasks } from '@/lib/ipc/tasks/lists';
import type { Task } from '@/lib/ipc/tasks/models';
import { compareTaskByPriorityThenDue } from '@/lib/tasks/taskComparators';

export interface ListViewProps {
  listId: string;
  /** Auto-enter rename mode on mount (e.g. from sidebar context menu). */
  initialRename?: boolean | undefined;
  onSelectTask?: ((taskId: string) => void) | undefined;
  onListDeleted?: (() => void) | undefined;
}

export type ListViewData = Awaited<ReturnType<typeof getListWithTasks>>;

export function sortOpenTasks(tasks: Task[]): Task[] {
  const ordered = [...tasks];
  ordered.sort(compareTaskByPriorityThenDue);
  return ordered;
}
