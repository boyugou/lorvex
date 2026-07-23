import { invoke, invokeIpc } from '@/lib/ipc/core';
import type { Task } from '../models';
import type { TaskWithRedo, TaskWithUndo } from './types';

export const completeTask = (id: string, signal?: AbortSignal): Promise<TaskWithUndo> =>
  invokeIpc('complete_task', { id }, signal);

export const reopenTask = (id: string, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('reopen_task', { id }, signal);

export const cancelTask = (id: string, cancelSeries?: boolean, signal?: AbortSignal): Promise<TaskWithUndo> =>
  invokeIpc('cancel_task', { id, cancel_series: cancelSeries ?? null }, signal);

export const undoTaskLifecycle = (token: string, signal?: AbortSignal): Promise<TaskWithRedo> =>
  invokeIpc('undo_task_lifecycle', { token }, signal);

export const undoTaskLifecycleBatch = (tokens: string[], signal?: AbortSignal): Promise<Task[]> =>
  invokeIpc('undo_task_lifecycle_batch', { tokens }, signal);

export const redoTaskLifecycle = (token: string, signal?: AbortSignal): Promise<TaskWithUndo> =>
  invokeIpc('redo_task_lifecycle', { token }, signal);

export const permanentDeleteTask = (id: string, signal?: AbortSignal): Promise<void> =>
  invokeIpc('permanent_delete_task', { id }, signal);

// --- Trash (soft-delete / Issue) ---

/**
 * Move a task to the Trash. The row stays in the DB but is hidden from
 * every user-facing query via `archived_at IS NOT NULL`. Use
 * `restoreTaskFromTrash` to undo within 30 days, after which the
 * boot-time auto-purge or manual `emptyTrash` hard-deletes it.
 */
export const archiveTask = (id: string, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('archive_task', { id }, signal);

export const restoreTaskFromTrash = (id: string, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('restore_task_from_trash', { id }, signal);

/**
 * Paginated Trash view. The `ArchivedTasksResult` envelope reports
 * `total_matching` so the UI can render "showing K of N — load
 * more" affordances and a user with thousands of trashed tasks
 * doesn't pay an unbounded `Vec<Task>` marshal cost on every
 * Trash-panel open.
 */
export interface ArchivedTasksResult {
  tasks: Task[];
  total_matching: number;
}

export const getArchivedTasks = (
  args: { limit?: number; offset?: number } = {},
  signal?: AbortSignal,
): Promise<ArchivedTasksResult> =>
  invoke('get_archived_tasks', args, signal);

export interface EmptyTrashResult {
  deleted: number;
  deleted_ids: string[];
  remaining: number;
}

export const emptyTrash = (signal?: AbortSignal): Promise<EmptyTrashResult> =>
  invokeIpc('empty_trash', {}, signal);
