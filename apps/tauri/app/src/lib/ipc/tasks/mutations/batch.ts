import { invokeIpc } from '@/lib/ipc/core';
import type { Task } from '../models';

interface BatchCompleteResult {
  completed_count: number;
  completed: Task[];
  undo_tokens: string[];
  skipped: string[];
}

export const batchCompleteTasks = (taskIds: string[], signal?: AbortSignal): Promise<BatchCompleteResult> =>
  invokeIpc('batch_complete_tasks', { task_ids: taskIds }, signal);

interface BatchCancelResult {
  cancelled_count: number;
  cancelled: Task[];
  undo_tokens: string[];
  skipped: string[];
}

export const batchCancelTasks = (taskIds: string[], cancelSeries?: boolean, signal?: AbortSignal): Promise<BatchCancelResult> =>
  invokeIpc('batch_cancel_tasks', { task_ids: taskIds, cancel_series: cancelSeries ?? null }, signal);

interface BatchDeferResult {
  deferred_count: number;
  deferred: Task[];
  skipped: string[];
}

export const batchDeferTasks = (
  taskIds: string[],
  untilDate: string,
  structuredReason?: string | null,
  signal?: AbortSignal,
): Promise<BatchDeferResult> =>
  invokeIpc(
    'batch_defer_tasks',
    { task_ids: taskIds, until_date: untilDate, structured_reason: structuredReason ?? null },
    signal,
  );

interface BatchMoveResult {
  moved_count: number;
  moved: Task[];
  skipped: string[];
}

export const batchMoveTasks = (
  taskIds: string[],
  targetListId: string | null,
  signal?: AbortSignal,
): Promise<BatchMoveResult> =>
  invokeIpc('batch_move_tasks', { task_ids: taskIds, target_list_id: targetListId }, signal);
