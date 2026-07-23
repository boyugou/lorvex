import { invoke } from '../core';

import type { DueReminderEntry, Task, TaskAttribution, TaskReminder } from './models';

export const getTask = (id: string, signal?: AbortSignal): Promise<Task | null> =>
  invoke('get_task', { id }, signal);

export const getTaskAttribution = (id: string, signal?: AbortSignal): Promise<TaskAttribution | null> =>
  invoke('get_task_attribution', { id }, signal);

/** Reverse-edge lookup: tasks whose depends_on contains the given task ID. */
export const getTasksBlockedBy = (taskId: string, signal?: AbortSignal): Promise<Task[]> =>
  invoke('get_tasks_blocked_by', { task_id: taskId }, signal);

export const searchTasks = (
  query: string,
  includeCancelled?: boolean,
  limit?: number,
  signal?: AbortSignal,
): Promise<Task[]> =>
  invoke('search_tasks', { query, include_cancelled: includeCancelled ?? false, limit: limit ?? null }, signal);

export const getSomedayTasks = (signal?: AbortSignal): Promise<Task[]> =>
  invoke('get_someday_tasks', undefined, signal);

/**
 * Every non-archived task that carries a recurrence rule. Powers the
 * Recurring Tasks index — a read-only dashboard listing every
 * active recurrence so power users can audit drift in one place.
 */
export const getRecurringTasks = (signal?: AbortSignal): Promise<Task[]> =>
  invoke('get_recurring_tasks', undefined, signal);

export const getUpcomingTasks = (days?: number, signal?: AbortSignal): Promise<Task[]> =>
  invoke('get_upcoming_tasks', { days: days ?? 7 }, signal);

export const getAllTasks = (
  includeCompleted?: boolean,
  includeCancelled?: boolean,
  signal?: AbortSignal,
): Promise<Task[]> =>
  invoke('get_all_tasks', {
    include_completed: includeCompleted ?? false,
    include_cancelled: includeCancelled ?? false,
  }, signal);

/** Today pool: open tasks whose planned_date or due_date puts them on or before today. */
export const getTodayPoolTasks = (signal?: AbortSignal): Promise<Task[]> =>
  invoke('get_today_pool_tasks', undefined, signal);

export const getOverdueTasks = (signal?: AbortSignal): Promise<Task[]> =>
  invoke('get_overdue_tasks', undefined, signal);

export const getDueReminders = (signal?: AbortSignal): Promise<DueReminderEntry[]> =>
  invoke('get_due_reminders', undefined, signal);

export const getTasksByDateRange = (
  from: string,
  to: string,
  includeCompleted?: boolean,
  signal?: AbortSignal,
): Promise<Task[]> =>
  invoke('get_tasks_by_date_range', {
    from,
    to,
    include_completed: includeCompleted ?? false,
  }, signal);

export const getUpcomingReminders = (withinSeconds?: number, signal?: AbortSignal): Promise<DueReminderEntry[]> =>
  invoke('get_upcoming_reminders', { within_seconds: withinSeconds }, signal);

export const getTaskReminders = (taskId: string, signal?: AbortSignal): Promise<TaskReminder[]> =>
  invoke('get_task_reminders', { task_id: taskId }, signal);

export const markReminderNotified = (id: string, signal?: AbortSignal): Promise<void> =>
  invoke('mark_reminder_notified', { id }, signal);

// ---------------------------------------------------------------------------
// Tags
// ---------------------------------------------------------------------------

export interface TagInfo {
  display_name: string;
  color: string | null;
}

export const getAllTags = (signal?: AbortSignal): Promise<TagInfo[]> =>
  invoke('get_all_tags', undefined, signal);
