import { invokeIpc } from '@/lib/ipc/core';
import type { TaskReminder } from '../models';

export const addTaskReminder = (taskId: string, reminderAt: string, signal?: AbortSignal): Promise<TaskReminder> =>
  invokeIpc('add_task_reminder', { task_id: taskId, reminder_at: reminderAt }, signal);

export const removeTaskReminder = (taskId: string, reminderId: string, signal?: AbortSignal): Promise<void> =>
  invokeIpc('remove_task_reminder', { task_id: taskId, reminder_id: reminderId }, signal);
