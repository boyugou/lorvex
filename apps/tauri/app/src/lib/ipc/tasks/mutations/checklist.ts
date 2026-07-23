import { invokeIpc } from '@/lib/ipc/core';
import type { TaskChecklistItem } from '../models';

export const addTaskChecklistItem = (taskId: string, text: string, signal?: AbortSignal): Promise<TaskChecklistItem> =>
  invokeIpc('add_task_checklist_item', { task_id: taskId, text }, signal);

export const updateTaskChecklistItemText = (
  taskId: string,
  itemId: string,
  text: string,
  signal?: AbortSignal,
): Promise<TaskChecklistItem> =>
  invokeIpc('update_task_checklist_item_text', { task_id: taskId, item_id: itemId, text }, signal);

export const setTaskChecklistItemCompleted = (
  taskId: string,
  itemId: string,
  completed: boolean,
  signal?: AbortSignal,
): Promise<TaskChecklistItem> =>
  invokeIpc('set_task_checklist_item_completed', {
    task_id: taskId,
    item_id: itemId,
    completed,
  }, signal);

export const removeTaskChecklistItem = (taskId: string, itemId: string, signal?: AbortSignal): Promise<void> =>
  invokeIpc('remove_task_checklist_item', { task_id: taskId, item_id: itemId }, signal);

export const reorderTaskChecklistItems = (
  taskId: string,
  itemIds: string[],
  signal?: AbortSignal,
): Promise<TaskChecklistItem[]> =>
  invokeIpc('reorder_task_checklist_items', { task_id: taskId, item_ids: itemIds }, signal);
