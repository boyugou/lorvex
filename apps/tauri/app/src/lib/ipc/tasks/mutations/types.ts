import type { Task } from '../models';

/** Result of complete_task / cancel_task with undo support. */
export interface TaskWithUndo {
  task: import('../models').Task;
  undo_token: string;
}

/**
 * Result of undo_task_lifecycle. The `redo_token` lets the UI
 * offer a one-step Redo affordance on the follow-up toast that fires
 * after the user clicks Undo. Invoking `redoTaskLifecycle(redo_token)`
 * re-applies the original lifecycle mutation and returns a fresh
 * `TaskWithUndo` — one level of back-and-forth, intentionally
 * non-stacking.
 */
export interface TaskWithRedo {
  task: import('../models').Task;
  redo_token: string | null;
}

interface TaskUpdateRecurrenceRule {
  FREQ: 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';
  INTERVAL?: number;
  BYDAY?: string[];
  BYMONTH?: number[];
  BYMONTHDAY?: number[];
  BYSETPOS?: number[];
  WKST?: string;
  UNTIL?: string;
  COUNT?: number;
}

interface TaskUpdatePatchFields {
  title: string;
  body: string | null;
  status: Task['status'];
  list_id: string;
  tags: string[] | null;
  priority: Task['priority'];
  due_date: string | null;
  due_time: string | null;
  planned_date: string | null;
  estimated_minutes: number | null;
  recurrence: TaskUpdateRecurrenceRule | null;
  depends_on: string[] | null;
  ai_notes: string | null;
}

export type TaskUpdatePatch = {
  [K in keyof TaskUpdatePatchFields]?: TaskUpdatePatchFields[K] | undefined;
};

export function stripUndefinedTaskUpdatePatch(patch: TaskUpdatePatch): TaskUpdatePatch {
  const projected: TaskUpdatePatch = {};
  for (const key of Object.keys(patch) as Array<keyof TaskUpdatePatch>) {
    const value = patch[key];
    if (value !== undefined) {
      (projected as Record<keyof TaskUpdatePatch, unknown>)[key] = value;
    }
  }
  return projected;
}
