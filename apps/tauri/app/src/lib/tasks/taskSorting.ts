import type { Task } from '@/lib/ipc/tasks/models';
import {
  compareTaskByDueThenPriority,
  compareTaskByPlannedDateThenPriority,
  compareTaskByActionDateThenPriority,
  compareTaskId,
  compareTaskIdentity,
  compareTaskByPriorityThenDue,
} from './taskComparators';

export type SortKey = 'default' | 'dueDate' | 'plannedDate' | 'priority' | 'actionDate' | 'completedAt' | 'createdAt' | 'title';
export type SortDirection = 'asc' | 'desc';

export const SORT_KEYS: SortKey[] = ['default', 'dueDate', 'plannedDate', 'priority', 'actionDate', 'completedAt', 'createdAt', 'title'];

export function resolveCompletedSectionSortDirection(sortKey: SortKey, sortDirection: SortDirection): SortDirection {
  return sortKey === 'default' ? 'desc' : sortDirection;
}

function compareTaskByCompletedAt(left: Task, right: Task): number {
  const completedAtCompare = (left.completed_at ?? '0000').localeCompare(right.completed_at ?? '0000');
  if (completedAtCompare !== 0) return completedAtCompare;
  return compareTaskId(left, right);
}

function compareTaskByCreatedAt(left: Task, right: Task): number {
  const createdAtCompare = left.created_at.localeCompare(right.created_at);
  if (createdAtCompare !== 0) return createdAtCompare;
  return compareTaskId(left, right);
}

function compareTaskByTitle(left: Task, right: Task): number {
  return compareTaskIdentity(left, right);
}

export function sortTasks(tasks: Task[], key: SortKey, direction: SortDirection = 'asc'): Task[] {
  if (key === 'default') return tasks;
  const sorted = [...tasks].sort((left, right) => {
    if (key === 'dueDate') {
      return compareTaskByDueThenPriority(left, right);
    }
    if (key === 'plannedDate') {
      return compareTaskByPlannedDateThenPriority(left, right);
    }
    if (key === 'priority') {
      return compareTaskByPriorityThenDue(left, right);
    }
    if (key === 'actionDate') {
      return compareTaskByActionDateThenPriority(left, right);
    }
    if (key === 'completedAt') {
      return compareTaskByCompletedAt(left, right);
    }
    if (key === 'createdAt') {
      return compareTaskByCreatedAt(left, right);
    }
    if (key === 'title') {
      return compareTaskByTitle(left, right);
    }
    return 0;
  });
  return direction === 'desc' ? sorted.reverse() : sorted;
}
