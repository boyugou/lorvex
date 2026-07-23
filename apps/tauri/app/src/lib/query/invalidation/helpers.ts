import type { QueryClient } from '@tanstack/react-query';
import type { DeviceStateKey } from '../../preferences/keys';

import { QUERY_KEYS } from '../queryKeyFactory';
import type { QueryKeyHead } from '../queryKeyHeads';
import { invalidateByKeyHeadSet, invalidateKeyHeads } from './batch';
import { EXTERNAL_MUTATION_QUERY_KEY_HEADS } from './groups';
import {
  queryKeyHeadsForInvalidationIntent,
  type QueryInvalidationIntent,
} from './registry';
import type {
  OptionalListIdInvalidationOptions,
  OptionalTaskAndListInvalidationOptions,
  TaskDependencyInvalidationOptions,
  TaskDetailWriteInvalidationOptions,
  TaskDetailWriteTarget,
} from './types';

// ---------------------------------------------------------------------------
// Registry-backed sets for high-traffic invalidation paths
// ---------------------------------------------------------------------------
// These are created once at module load so that the hot paths only need a
// single `invalidateByKeyHeadSet` call per invocation.

const EXTERNAL_MUTATION_SET = new Set<QueryKeyHead>(EXTERNAL_MUTATION_QUERY_KEY_HEADS);

function invalidateQueryIntent(
  queryClient: QueryClient,
  intent: QueryInvalidationIntent,
): void {
  invalidateKeyHeads(queryClient, queryKeyHeadsForInvalidationIntent(intent));
}

// ---------------------------------------------------------------------------
// Public invalidation helpers
// ---------------------------------------------------------------------------

export function invalidateTodaySurfaceQueries(queryClient: QueryClient): void {
  invalidateQueryIntent(queryClient, 'today.surface');
}

export function invalidateExternalMutationQueries(queryClient: QueryClient): void {
  invalidateByKeyHeadSet(queryClient, EXTERNAL_MUTATION_SET);
}

export function invalidateTaskCollectionQueries(queryClient: QueryClient): void {
  invalidateQueryIntent(queryClient, 'task.collection');
}

export function invalidateTaskWorkspaceQueries(queryClient: QueryClient): void {
  invalidateQueryIntent(queryClient, 'task.workspace');
}

export function invalidateDataImportQueries(queryClient: QueryClient): void {
  invalidateQueryIntent(queryClient, 'data.import');
}

export function invalidateTaskMutationQueries(
  queryClient: QueryClient,
  options?: OptionalListIdInvalidationOptions,
): void {
  invalidateQueryIntent(queryClient, 'task.write');

  if (options?.listId !== null && options?.listId !== undefined) {
    void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.list(options.listId) });
  }
}

// Shared list-context task writes (quick capture, reorder, in-list add) to prevent
// per-component key drift in invalidation sets.
export function invalidateListContextTaskWriteQueries(
  queryClient: QueryClient,
  options?: OptionalListIdInvalidationOptions,
): void {
  invalidateQueryIntent(queryClient, 'list.contextTaskWrite');

  if (options?.listId !== null && options?.listId !== undefined) {
    void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.list(options.listId) });
  }
}

// ---------------------------------------------------------------------------
// Domain-level invalidation helpers
// ---------------------------------------------------------------------------

/** Invalidate all queries — used after destructive resets (e.g. DangerZone). */
export function invalidateAllQueries(queryClient: QueryClient): void {
  void queryClient.invalidateQueries();
}

/** AI changelog views. */
export function invalidateChangelogQueries(queryClient: QueryClient): void {
  void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.aiChangelog() });
}

export function invalidateDailyReviewQueries(queryClient: QueryClient): void {
  invalidateQueryIntent(queryClient, 'dailyReview.write');
}

export function invalidateHabitQueries(queryClient: QueryClient): void {
  invalidateQueryIntent(queryClient, 'habit.write');
}

export function invalidateHabitReminderQueries(queryClient: QueryClient): void {
  void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.habitReminderPolicies() });
}

/** Preference queries — optionally scoped to a single preference key. */
export function invalidatePreferenceQueries(
  queryClient: QueryClient,
  options?: { key?: string },
): void {
  if (options?.key) {
    void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.preference(options.key) });
  } else {
    void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.preferenceRoot() });
  }
}

export function invalidateCalendarMutationQueries(queryClient: QueryClient): void {
  // also refresh the task-detail
  // event-link search popover and the single-event detail queries so
  // a local create/delete reflects across every view in lockstep.
  invalidateQueryIntent(queryClient, 'calendar.eventWrite');
}

/** Calendar subscriptions + their events.
 * subscription ops (sync / toggle / remove) are a
 *  superset of regular event ops — they add, hide, or cascade-delete
 *  potentially many events at once. Must invalidate at least what a
 *  regular calendar mutation does. */
export function invalidateCalendarSubscriptionQueries(queryClient: QueryClient): void {
  // also refresh calendarTasks and
  // eventsUnifiedForLinkSearch so a toggle/remove cascade reflects in
  // the task-plus-events unified view and the task-detail event-link
  // search popover.
  invalidateQueryIntent(queryClient, 'calendar.subscriptionWrite');
}

/** Calendar view (tasks + events + today surface). */
export function invalidateCalendarViewQueries(queryClient: QueryClient): void {
  invalidateQueryIntent(queryClient, 'calendar.view');
}

/** Focus schedule mutations (schedule-only, no overview). */
export function invalidateFocusScheduleQueries(queryClient: QueryClient): void {
  invalidateQueryIntent(queryClient, 'focus.schedule');
}

/** Focus schedule mutations that also affect current-focus and overview. */
export function invalidatePlanningFocusQueries(queryClient: QueryClient): void {
  invalidateQueryIntent(queryClient, 'focus.planning');
}

/** Task status changes in board views (kanban, eisenhower). */
export function invalidateTaskStatusChangeQueries(queryClient: QueryClient): void {
  invalidateQueryIntent(queryClient, 'task.statusChange');
}

/** Focus mode task writes (today-surface + all-tasks).
 *  For task-specific + list-specific keys, callers pass options. */
export function invalidateFocusTaskQueries(
  queryClient: QueryClient,
  options?: OptionalTaskAndListInvalidationOptions,
): void {
  invalidateQueryIntent(queryClient, 'focus.taskWrite');
  if (options?.taskId) {
    void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.task(options.taskId) });
  }
  if (options?.listId) {
    void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.list(options.listId) });
  }
}

/** Task detail panel writes — the full invalidation set used by the detail controller. */
export function invalidateTaskDetailWriteQueries(
  queryClient: QueryClient,
  task: TaskDetailWriteTarget,
  options?: TaskDetailWriteInvalidationOptions,
): void {
  invalidateTaskMutationQueries(queryClient, { listId: task.list_id });
  invalidateQueryIntent(queryClient, 'task.detailWrite.extra');
  for (const listId of options?.extraListIds ?? []) {
    if (listId == null || listId === task.list_id) continue;
    void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.list(listId) });
  }
}

// ---------------------------------------------------------------------------
// Leaf / entity-level invalidation helpers
// ---------------------------------------------------------------------------
// These target a single entity by ID (or a single keyHead with no sub-key).
// Components MUST use these instead of raw `invalidateQueries` calls.

/** Single task detail query: `['task', taskId]`. */
export function invalidateTaskQueries(
  queryClient: QueryClient,
  taskId: string,
): void {
  void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.task(taskId) });
}

/** Single list query: `['list', listId]`. */
export function invalidateListQueries(
  queryClient: QueryClient,
  listId: string,
): void {
  void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.list(listId) });
}

/** Today bootstrap query: `['today-bootstrap']`. */
export function invalidateTodayBootstrapQueries(queryClient: QueryClient): void {
  void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.todayBootstrap() });
}

/** Overview query: `['overview']`. */
export function invalidateOverviewQueries(queryClient: QueryClient): void {
  void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.overview() });
}

/** Current focus query: `['current-focus']`. */
export function invalidateCurrentFocusQueries(queryClient: QueryClient): void {
  void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.currentFocus() });
}

/** Task dependency writes touch both endpoint task-detail and blocked-by queries. */
export function invalidateTaskDependencyQueries(
  queryClient: QueryClient,
  options: TaskDependencyInvalidationOptions,
): void {
  invalidateQueryIntent(queryClient, 'task.dependencyWrite');
  const taskIds = new Set(
    [options.taskId, options.relatedTaskId]
      .filter((value): value is string => typeof value === 'string' && value.length > 0),
  );
  for (const taskId of taskIds) {
    void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.task(taskId) });
    void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.tasksBlockedBy(taskId) });
  }
}

/** Task reminders for a specific task: `['task-reminders', taskId]`. */
export function invalidateTaskReminderQueries(
  queryClient: QueryClient,
  taskId: string,
): void {
  void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.taskReminders(taskId) });
}

/** Device state for a specific key: `['device-state', key]`. */
export function invalidateDeviceStateQueries(
  queryClient: QueryClient,
  key: DeviceStateKey,
): void {
  void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.deviceState(key) });
}
