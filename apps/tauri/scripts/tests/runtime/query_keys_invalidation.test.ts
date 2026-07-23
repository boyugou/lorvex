import assert from 'node:assert/strict';
import test from 'node:test';

import { QueryClient } from '@tanstack/react-query';

import {
  QK,
  QUERY_INVALIDATION_REGISTRY,
  invalidateCalendarMutationQueries,
  invalidateCalendarSubscriptionQueries,
  invalidateFocusTaskQueries,
  invalidateHabitReminderQueries,
  invalidateOverviewQueries,
  invalidateQueriesForEntity,
  invalidateTaskDependencyQueries,
  invalidateTaskMutationQueries,
  invalidateTodayBootstrapQueries,
  queryKeyHeadsForInvalidationIntent,
} from '../../../app/src/lib/query/queryKeys';

const REPRESENTATIVE_QUERY_KEYS = [
  [QK.calendarEvents, '2026-04-01', '2026-04-30'],
  [QK.calendarEvent, 'event-1'],
  [QK.calendarTasks, '2026-04-01', '2026-04-30'],
  [QK.todayEvents, '2026-04-22'],
  [QK.upcomingEvents, '2026-04-22', '2026-04-29'],
  [QK.weeklyReview],
  [QK.weeklyReviewEvents, '2026-04-22', '2026-04-29'],
  [QK.taskEventLinks, 'task-1'],
  [QK.taskProviderEventLinks, 'task-1'],
  [QK.eventsUnifiedForLinkSearch, '2026-04-15', '2026-05-22'],
  [QK.calendarSubscriptions],
  [QK.search, 'unrelated'],
  [QK.overview],
  [QK.lists],
  [QK.list, 'list-1'],
  [QK.list, 'list-2'],
  [QK.currentFocus],
  [QK.focusSchedule],
  [QK.preference, 'timezone'],
  [QK.deviceState, 'notification_permission_granted'],
  [QK.setupStatus],
  [QK.todayBootstrap],
  [QK.allTasks, false, false],
  [QK.somedayTasks],
  [QK.recurringTasks],
  [QK.upcomingTasks, '2026-04-22'],
  [QK.upcomingWeekTasks, '2026-04-22', 7],
  [QK.task, 'task-1'],
  [QK.task, 'task-2'],
  [QK.task, 'task-3'],
  [QK.taskAttribution, 'task-1'],
  [QK.taskAttribution, 'task-3'],
  [QK.tasksBlockedBy, 'task-1'],
  [QK.tasksBlockedBy, 'task-2'],
  [QK.tasksBlockedBy, 'task-3'],
  [QK.taskReminders, 'task-1'],
  [QK.habitReminderPolicies],
  [QK.weeklyReviewUpcoming],
  [QK.savedQueries, 'AllTasks'],
] as const;

function buildQueryClient(): QueryClient {
  const queryClient = new QueryClient();
  for (const queryKey of REPRESENTATIVE_QUERY_KEYS) {
    queryClient.setQueryData(queryKey, { ok: true });
  }
  return queryClient;
}

function queryKeyId(queryKey: readonly unknown[]): string {
  return JSON.stringify(queryKey);
}

function headsFromKeyIds(queryKeyIds: Set<string>): Set<string> {
  return new Set(
    Array.from(queryKeyIds, (queryKeyIdValue) => {
      const queryKey = JSON.parse(queryKeyIdValue);
      assert.equal(Array.isArray(queryKey), true);
      return String(queryKey[0]);
    }),
  );
}

async function invalidatedKeyIdsAfter(
  runner: (queryClient: QueryClient) => void,
): Promise<Set<string>> {
  const queryClient = buildQueryClient();
  runner(queryClient);
  await new Promise((resolve) => setTimeout(resolve, 0));

  return new Set(
    queryClient
      .getQueryCache()
      .getAll()
      .filter((query) => query.state.isInvalidated)
      .map((query) => queryKeyId(query.queryKey))
      .sort(),
  );
}

async function invalidatedHeadsAfter(
  runner: (queryClient: QueryClient) => void,
): Promise<Set<string>> {
  return headsFromKeyIds(await invalidatedKeyIdsAfter(runner));
}

test('calendar_event entity invalidation matches the local calendar mutation helper contract', async () => {
  const localHeads = await invalidatedHeadsAfter((queryClient) => {
    invalidateCalendarMutationQueries(queryClient);
  });
  const externalHeads = await invalidatedHeadsAfter((queryClient) => {
    invalidateQueriesForEntity(queryClient, 'calendar_event');
  });

  assert.deepEqual(externalHeads, localHeads);
  assert.equal(externalHeads.has(QK.calendarEvent), true);
  assert.equal(externalHeads.has(QK.upcomingEvents), true);
  assert.equal(externalHeads.has(QK.calendarTasks), true);
  assert.equal(externalHeads.has(QK.search), false);
});

test('calendar_subscription entity invalidation matches the local subscription mutation helper contract', async () => {
  const localHeads = await invalidatedHeadsAfter((queryClient) => {
    invalidateCalendarSubscriptionQueries(queryClient);
  });
  const externalHeads = await invalidatedHeadsAfter((queryClient) => {
    invalidateQueriesForEntity(queryClient, 'calendar_subscription');
  });

  assert.deepEqual(externalHeads, localHeads);
  assert.equal(externalHeads.has(QK.calendarSubscriptions), true);
  assert.equal(externalHeads.has(QK.calendarEvent), true);
  assert.equal(externalHeads.has(QK.weeklyReviewEvents), true);
  assert.equal(externalHeads.has(QK.search), false);
});

test('registry exposes representative task list focus and calendar mutation intents', () => {
  assert.deepEqual(
    queryKeyHeadsForInvalidationIntent('calendar.eventWrite'),
    QUERY_INVALIDATION_REGISTRY['calendar.eventWrite'],
  );
  assert.equal(queryKeyHeadsForInvalidationIntent('task.write').includes(QK.search), true);
  assert.equal(queryKeyHeadsForInvalidationIntent('task.dependencyWrite').includes(QK.todayBootstrap), true);
  assert.equal('list.create' in QUERY_INVALIDATION_REGISTRY, false);
  assert.equal(queryKeyHeadsForInvalidationIntent('focus.taskWrite').includes(QK.currentFocus), true);
  assert.equal(queryKeyHeadsForInvalidationIntent('calendar.subscriptionWrite').includes(QK.calendarSubscriptions), true);
});

test('preference entity invalidates saved query caches used by backend saved-query broadcasts', async () => {
  const heads = await invalidatedHeadsAfter((queryClient) => {
    invalidateQueriesForEntity(queryClient, 'preference');
  });

  assert.equal(heads.has(QK.preference), true);
  assert.equal(heads.has(QK.deviceState), true);
  assert.equal(heads.has(QK.setupStatus), true);
  assert.equal(heads.has(QK.savedQueries), true);
});

test('task write helper follows the registry task.write intent plus scoped list keys', async () => {
  const heads = await invalidatedHeadsAfter((queryClient) => {
    invalidateTaskMutationQueries(queryClient, { listId: 'list-1' });
  });

  assert.equal(heads.has(QK.search), true);
  assert.equal(heads.has(QK.task), true);
  assert.equal(heads.has(QK.weeklyReviewUpcoming), true);
  assert.equal(heads.has(QK.list), true);
  assert.equal(heads.has(QK.calendarEvent), false);
});

test('focus task helper follows its registry intent', async () => {
  const focusHeads = await invalidatedHeadsAfter((queryClient) => {
    invalidateFocusTaskQueries(queryClient, { taskId: 'task-1', listId: 'list-1' });
  });

  assert.equal(focusHeads.has(QK.currentFocus), true);
  assert.equal(focusHeads.has(QK.todayBootstrap), true);
  assert.equal(focusHeads.has(QK.task), true);
  assert.equal(focusHeads.has(QK.list), true);
});

test('task dependency and today bootstrap helpers replace raw component invalidations', async () => {
  const dependencyKeyIds = await invalidatedKeyIdsAfter((queryClient) => {
    invalidateTaskDependencyQueries(queryClient, { taskId: 'task-1', relatedTaskId: 'task-2' });
  });
  const externalDependencyKeyIds = await invalidatedKeyIdsAfter((queryClient) => {
    invalidateQueriesForEntity(queryClient, 'task_dependency');
  });
  const bootstrapHeads = await invalidatedHeadsAfter((queryClient) => {
    invalidateTodayBootstrapQueries(queryClient);
  });
  const dependencyHeads = headsFromKeyIds(dependencyKeyIds);

  assert.deepEqual(dependencyKeyIds, externalDependencyKeyIds);
  assert.equal(dependencyHeads.has(QK.task), true);
  assert.equal(dependencyHeads.has(QK.tasksBlockedBy), true);
  assert.equal(dependencyHeads.has(QK.allTasks), true);
  assert.equal(dependencyHeads.has(QK.todayBootstrap), true);
  assert.equal(dependencyHeads.has(QK.currentFocus), true);
  assert.equal(dependencyHeads.has(QK.calendarEvent), false);
  assert.equal(dependencyKeyIds.has(queryKeyId([QK.task, 'task-3'])), true);
  assert.equal(dependencyKeyIds.has(queryKeyId([QK.tasksBlockedBy, 'task-3'])), true);
  assert.equal(bootstrapHeads.has(QK.todayBootstrap), true);
  assert.equal(bootstrapHeads.has(QK.currentFocus), false);
});

test('leaf invalidation helpers keep contract-retained query surfaces live', async () => {
  const overviewHeads = await invalidatedHeadsAfter((queryClient) => {
    invalidateOverviewQueries(queryClient);
  });
  const habitReminderHeads = await invalidatedHeadsAfter((queryClient) => {
    invalidateHabitReminderQueries(queryClient);
  });

  assert.deepEqual(overviewHeads, new Set([QK.overview]));
  assert.deepEqual(habitReminderHeads, new Set([QK.habitReminderPolicies]));
});
