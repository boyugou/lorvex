import type { Task } from '@/lib/ipc/tasks/models';

type DueAtTask = Pick<Task, 'due_date' | 'due_time'>;

export type DueAtPatch =
  | { due_date: string | null; due_time?: string | null }
  | { due_time: string | null; due_date?: string | null };

export function buildDueDatePatch(task: DueAtTask, dueDate: string | null): DueAtPatch {
  if (dueDate === null && task.due_time !== null) {
    return { due_date: null, due_time: null };
  }
  return { due_date: dueDate };
}

export function buildDueTimePatch(
  task: DueAtTask,
  dueTime: string | null,
  fallbackDueDate: string,
): DueAtPatch {
  if (dueTime === null) {
    return { due_time: null };
  }
  if (task.due_date !== null) {
    return { due_time: dueTime };
  }
  return { due_date: fallbackDueDate, due_time: dueTime };
}
