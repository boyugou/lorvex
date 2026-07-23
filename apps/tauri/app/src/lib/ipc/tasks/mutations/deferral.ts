import { invokeIpc } from '@/lib/ipc/core';

import type { DeferReason } from '@lorvex/shared/types';

import type { Task } from '../models';

export const deferTask = (id: string, structuredReason?: DeferReason | null, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('defer_task', { id, structured_reason: structuredReason ?? null }, signal);

export const deferTaskUntil = (id: string, untilDate: string, structuredReason?: DeferReason | null, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('defer_task_until', { id, until_date: untilDate, structured_reason: structuredReason ?? null }, signal);

export const resetTaskDeferral = (id: string, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('reset_task_deferral', { id }, signal);

/**
 * Snapshot of a task's deferral fields captured by the UI immediately
 * before a `deferTaskUntil` call, passed back to the backend so the
 * "Undo" toast can restore the EXACT pre-defer state. Matches the
 * `DeferralSnapshot` struct in `app/src-tauri/src/commands/task_commands/
 * lifecycle/deferral.rs`.
 */
export interface DeferralSnapshot {
  planned_date: string | null;
  defer_count: number;
  last_deferred_at: string | null;
  last_defer_reason: string | null;
}

export const restoreTaskDeferral = (id: string, snapshot: DeferralSnapshot, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('restore_task_deferral', { id, snapshot }, signal);
