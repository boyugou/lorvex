import { invokeIpc } from '@/lib/ipc/core';
import type { Task } from '../models';

// --- Atomic dependency manipulation ---

export const addTaskDependency = (taskId: string, dependsOnTaskId: string, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('add_task_dependency', { task_id: taskId, depends_on_task_id: dependsOnTaskId }, signal);

export const removeTaskDependency = (taskId: string, dependsOnTaskId: string, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('remove_task_dependency', { task_id: taskId, depends_on_task_id: dependsOnTaskId }, signal);
