import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';

/**
 * Shared types for task-card context-menu helpers.
 *
 * `ActionHelpers` is the canonical helper-bag passed to every menu-item
 * builder (defer, due-date, priority, recurrence, duration, move-to-list,
 * etc.). Builders consume the subset they need via `Pick<ActionHelpers, ...>`
 * — see `buildMoveToListMenuItem` taking `Pick<ActionHelpers, 'runAction'>`
 * and `buildPriorityMenuItem` taking `Pick<ActionHelpers, 'runUpdate'>`.
 */

/**
 * Apply a partial-update mutation to a task and report the outcome via
 * toast. Wraps `updateTask(id, updates)` plus error logging plus a
 * success toast.
 */
export type RunUpdate = (
  updates: TaskUpdatePatch,
  source: string,
  errorMessage: string,
  successToast?: string,
) => void;

/**
 * Run an arbitrary mutation promise (not necessarily an update) and
 * report the outcome via toast. Used by handlers that need a different
 * IPC than `updateTask` (e.g. `deferTaskUntil`, list moves).
 *
 * `extraListIds` lets the caller invalidate caches for additional list
 * IDs touched by the action — e.g. moving a task between lists must
 * invalidate both source and destination.
 */
type RunAction = (
  action: Promise<unknown>,
  source: string,
  errorMessage: string,
  successToast?: string,
  extraListIds?: Array<string | null | undefined>,
) => void;

/**
 * Helper bag passed to every task-card context-menu builder. Builders
 * that need only a subset use `Pick<ActionHelpers, ...>` to make the
 * dependency explicit at the call site.
 */
export interface ActionHelpers {
  runAction: RunAction;
  runUpdate: RunUpdate;
  invalidate: (listId?: string | null) => void;
}
