import type { Task } from '@/lib/ipc/tasks/models';

// Re-export sort types from the shared module so existing imports
// (`from './types'`) continue to work.
export type { SortKey, SortDirection } from '@/lib/tasks/taskSorting';
export { SORT_KEYS } from '@/lib/tasks/taskSorting';

export type GroupBy = 'status' | 'list' | 'due_date' | 'priority' | 'tag';
export type { BulkAction } from '@/lib/tasks/useTaskSelection';

export const GROUP_BY_KEYS: GroupBy[] = ['status', 'list', 'due_date', 'priority', 'tag'];

export interface TaskSection {
  key: string;
  title: string;
  tasks: Task[];
  completed?: boolean | undefined;
}
