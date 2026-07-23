import { invokeIpc } from '@/lib/ipc/core';
import type { CurrentFocusWithTasks } from '../models';

export const reorderCurrentFocusOpenTasks = (openTaskIds: string[], signal?: AbortSignal): Promise<CurrentFocusWithTasks> =>
  invokeIpc('reorder_current_focus_open_tasks', { open_task_ids: openTaskIds }, signal);

export const addToCurrentFocus = (taskIds: string[], signal?: AbortSignal): Promise<CurrentFocusWithTasks> =>
  invokeIpc('add_to_current_focus', { task_ids: taskIds }, signal);
