import type { QueryClient } from '@tanstack/react-query';

import { QK, type QueryKeyHead } from '../queryKeyHeads';
import { queryHeadList, invalidateKeyHeads } from './batch';
import { TASK_COLLECTION_QUERY_KEY_HEADS } from './groups';
import { invalidateExternalMutationQueries } from './helpers';
import { QUERY_INVALIDATION_REGISTRY } from './registry';

export const QUERY_ENTITY_INVALIDATION_MAP: Record<string, readonly QueryKeyHead[]> = {
  // Canonical entity types (must match naming registry in shared/src/types.ts)
  // weekly review panels (QK.weeklyReview, …Upcoming,
  // …Events, …Habits) were missing from every per-entity map, so any
  // mutation left the open Weekly Review view stale until unmount.
  // Added in each relevant row below.
  // QK.tasksBlockedBy + QK.allTags added to task/task_tag
  // maps so completing a blocker or creating a task with a new tag
  // refreshes the blocked-by panel and tag-suggestion dropdown.
  task: queryHeadList(
    ...QUERY_INVALIDATION_REGISTRY['today.surface'],
    ...QUERY_INVALIDATION_REGISTRY['task.collection'],
    ...QUERY_INVALIDATION_REGISTRY['task.detail'],
    QK.search,
    QK.taskReminders,
    QK.tasksBlockedBy,
    QK.allTags,
    QK.weeklyReview,
    QK.weeklyReviewUpcoming,
  ),
  list: queryHeadList(
    QK.lists,
    QK.list,
    ...QUERY_INVALIDATION_REGISTRY['today.surface'],
    QK.weeklyReview,
  ),
  calendar_event: QUERY_INVALIDATION_REGISTRY['calendar.eventWrite'],
  calendar_subscription: QUERY_INVALIDATION_REGISTRY['calendar.subscriptionWrite'],
  task_calendar_event_link: queryHeadList(QK.taskEventLinks, QK.taskProviderEventLinks),
  task_tag: queryHeadList(
    ...QUERY_INVALIDATION_REGISTRY['today.surface'],
    ...QUERY_INVALIDATION_REGISTRY['task.collection'],
    ...QUERY_INVALIDATION_REGISTRY['task.detail'],
    QK.search,
    QK.allTags,
  ),
  task_dependency: QUERY_INVALIDATION_REGISTRY['task.dependencyWrite'],
  task_checklist_item: queryHeadList(...QUERY_INVALIDATION_REGISTRY['task.write']),
  habit: queryHeadList(
    QK.todaysHabits,
    QK.habitsWithStats,
    QK.habitReminderPolicies,
    QK.weeklyReview,
    QK.weeklyReviewHabits,
  ),
  habit_completion: queryHeadList(QK.todaysHabits, QK.habitsWithStats, QK.weeklyReviewHabits),
  tag: queryHeadList(
    ...QUERY_INVALIDATION_REGISTRY['today.surface'],
    ...TASK_COLLECTION_QUERY_KEY_HEADS,
    ...QUERY_INVALIDATION_REGISTRY['task.detail'],
    QK.search,
    QK.allTags,
  ),
  daily_review: queryHeadList(
    QK.dailyReviews,
    QK.dailyReview,
    ...QUERY_INVALIDATION_REGISTRY['today.surface'],
  ),
  current_focus: QUERY_INVALIDATION_REGISTRY['today.surface'],
  focus_schedule: QUERY_INVALIDATION_REGISTRY['today.surface'],
  // setupStatus is a computed projection over PREF_SETUP_COMPLETED
  // et al., so a preference write must invalidate it too. Otherwise the
  // first-run screen stays forever (staleTime: Infinity, refetchInterval: false).
  // Saved-query writes currently broadcast Entity::Preference from
  // the Rust event bus, so cross-window listeners must refresh saved
  // filter menus through the same entity path.
  // Device-state writes also broadcast Entity::Preference today, so
  // notification permission, native calendar, and focus heartbeat
  // readers need the same path.
  preference: queryHeadList(
    QK.preference,
    QK.deviceState,
    QK.dashboardLayout,
    QK.setupStatus,
    QK.savedQueries,
  ),
  memory: queryHeadList(QK.aiMemory),
  memory_revision: queryHeadList(QK.aiMemory, QK.memoryHistory),
  task_reminder: queryHeadList(QK.taskReminders, ...QUERY_INVALIDATION_REGISTRY['today.surface']),
  habit_reminder_policy: queryHeadList(QK.habitReminderPolicies),
  ai_changelog: queryHeadList(QK.aiChangelog),
  // Rust event_bus Entity enum aliases (serialized as snake_case)
  changelog: queryHeadList(QK.aiChangelog),
  // Rust collapses both memory + memory_revision into
  // Entity::AiMemory when emitting, so this alias must cover the
  // history head too — otherwise the HistoryModal stays stale when a
  // peer writes a memory revision.
  ai_memory: queryHeadList(QK.aiMemory, QK.memoryHistory),
  data_import: queryHeadList(
    ...QUERY_INVALIDATION_REGISTRY['today.surface'],
    ...QUERY_INVALIDATION_REGISTRY['task.collection'],
    ...QUERY_INVALIDATION_REGISTRY['task.detail'],
  ),
  planning: QUERY_INVALIDATION_REGISTRY['today.surface'],
};

export function invalidateQueriesForEntity(queryClient: QueryClient, entity: string): void {
  const keyHeads = QUERY_ENTITY_INVALIDATION_MAP[entity];
  if (keyHeads) { invalidateKeyHeads(queryClient, keyHeads); }
  else { invalidateExternalMutationQueries(queryClient); }
}
