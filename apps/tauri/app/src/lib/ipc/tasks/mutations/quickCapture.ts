import { invokeIpc } from '@/lib/ipc/core';
import type { Task } from '../models';
import { stripUndefinedTaskUpdatePatch, type TaskUpdatePatch, type TaskWithUndo } from './types';

export interface QuickCaptureInput {
  title: string;
  listId?: string | undefined;
  dueDate?: string | undefined;
  priority?: number | null | undefined;
  estimatedMinutes?: number | null | undefined;
  body?: string | undefined;
  tags?: string[] | null | undefined;
  status?: 'open' | 'someday' | undefined;
  signal?: AbortSignal | undefined;
}

export const quickCapture = ({
  title,
  listId,
  dueDate,
  priority,
  estimatedMinutes,
  body,
  tags,
  status,
  signal,
}: QuickCaptureInput): Promise<Task> =>
  invokeIpc('quick_capture', {
    request: {
      title,
      list_id: listId ?? null,
      due_date: dueDate ?? null,
      priority: priority ?? null,
      estimated_minutes: estimatedMinutes ?? null,
      body: body ?? null,
      tags: tags ?? null,
      status: status ?? null,
    },
  }, signal);

export const duplicateTask = (id: string, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('duplicate_task', { id }, signal);

/**
 * Update one or more fields on a task. Returns a `TaskWithUndo`:
 * every non-bookkeeping mutation mints an undo token carrying the
 * pre-mutation snapshot so the UI can show a Success toast with Undo.
 */
export const updateTask = (id: string, updates: TaskUpdatePatch, signal?: AbortSignal): Promise<TaskWithUndo> =>
  invokeIpc('update_task', { id, updates: stripUndefinedTaskUpdatePatch(updates) }, signal);
