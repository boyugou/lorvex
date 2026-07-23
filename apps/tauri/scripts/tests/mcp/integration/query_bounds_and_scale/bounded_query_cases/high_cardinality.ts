import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createHarness,
  daysFromTodayYmd,
  parseJsonContent,
} from '../../shared';

test('high-cardinality query tools remain bounded and expose truncation metadata', async (t) => {
  const harness = await createHarness('high-cardinality-bounds');
  t.after(async () => {
    await harness.cleanup();
  });

  const listResult = await harness.client.callTool({
    name: 'create_list',
    arguments: {
      name: 'Scale Resilience List',
    },
  });
  const list = parseJsonContent<{ id: string }>(listResult);

  const today = daysFromTodayYmd();
  const tomorrow = daysFromTodayYmd(1);
  const createSeedTasks = async (
    prefix: string,
    count: number,
    overrides: Record<string, unknown> = {},
  ): Promise<Array<{ id: string; status: string }>> => {
    const batchSize = 25;
    const created: Array<{ id: string; status: string }> = [];

    for (let start = 0; start < count; start += batchSize) {
      const size = Math.min(batchSize, count - start);
      const tasks = Array.from({ length: size }, (_, offset) => ({
        title: `${prefix}-${start + offset}`,
        list_id: list.id,
        raw_input: 'stream-a issue #92 scale resilience seed',
        ...overrides,
      }));

      const createResult = await harness.client.callTool({
        name: 'batch_create_tasks',
        arguments: { tasks },
      });
      const createdPayload = parseJsonContent<{
        created_count: number;
        tasks: Array<{ id: string; status: string }>;
      }>(createResult);
      assert.equal(createdPayload.created_count, size);
      assert.equal(createdPayload.tasks.length, size);
      created.push(...createdPayload.tasks);
    }

    return created;
  };

  await createSeedTasks('scale-overdue', 20, { due_date: '2000-01-01' });
  await createSeedTasks('scale-due-today', 20, { due_date: today });
  await createSeedTasks('scale-upcoming', 20, { due_date: tomorrow });
  const deferredTasks = await createSeedTasks('scale-deferred', 20);

  // Defer all tasks using batch_defer_tasks (sets defer_count >= 1, keeps status open).
  // Pick a deterministic absolute target 7 days from today (YYYY-MM-DD).
  // canonical UTC-anchored helper; previous inline UTC-slice
  // disagreed with shared/time.ts's local-tz helper on midnight days.
  const deferUntilDate = daysFromTodayYmd(7);
  const deferredUpdateResult = await harness.client.callTool({
    name: 'batch_defer_tasks',
    arguments: {
      task_ids: deferredTasks.map((task) => task.id),
      until_date: deferUntilDate,
    },
  });
  const deferredUpdatePayload = parseJsonContent<{
    deferred_count: number;
    deferred: Array<{ id: string; status: string; defer_count: number }>;
  }>(deferredUpdateResult);
  assert.equal(deferredUpdatePayload.deferred_count, deferredTasks.length);
  assert.equal(deferredUpdatePayload.deferred.length, deferredTasks.length);
  assert.ok(deferredUpdatePayload.deferred.every((task) => task.status === 'open' && task.defer_count >= 1));

  const listTasksResult = await harness.client.callTool({
    name: 'list_tasks',
    arguments: {
      list_id: list.id,
      status: 'open',
      limit: 9,
    },
  });
  const listTasksPayload = parseJsonContent<{
    limit: number;
    count: number;
    returned: number;
    total_matching: number;
    truncated: boolean;
    tasks: Array<{ id: string }>;
  }>(listTasksResult);
  assert.equal(listTasksPayload.limit, 9);
  assert.equal(listTasksPayload.count, 9);
  assert.equal(listTasksPayload.returned, 9);
  assert.equal(listTasksPayload.tasks.length, 9);
  assert.equal(listTasksPayload.truncated, true);
  assert.equal(listTasksPayload.truncated, listTasksPayload.total_matching > listTasksPayload.count);

  const searchTasksResult = await harness.client.callTool({
    name: 'search_tasks',
    arguments: {
      query: 'scale-',
      status: 'all',
      limit: 11,
    },
  });
  const searchTasksPayload = parseJsonContent<{
    limit: number;
    count: number;
    returned: number;
    total_matching: number;
    truncated: boolean;
    tasks: Array<{ id: string }>;
  }>(searchTasksResult);
  assert.equal(searchTasksPayload.limit, 11);
  assert.equal(searchTasksPayload.count, 11);
  assert.equal(searchTasksPayload.returned, 11);
  assert.equal(searchTasksPayload.tasks.length, 11);
  assert.equal(searchTasksPayload.truncated, true);
  assert.equal(searchTasksPayload.truncated, searchTasksPayload.total_matching > searchTasksPayload.count);

  const deferredResult = await harness.client.callTool({
    name: 'get_deferred_tasks',
    arguments: {
      list_id: list.id,
      limit: 6,
    },
  });
  const deferredPayload = parseJsonContent<{
    limit: number;
    count: number;
    returned: number;
    total_matching: number;
    truncated: boolean;
    tasks: Array<{ id: string; status: string }>;
  }>(deferredResult);
  assert.equal(deferredPayload.limit, 6);
  assert.equal(deferredPayload.count, 6);
  assert.equal(deferredPayload.returned, 6);
  assert.equal(deferredPayload.tasks.length, 6);
  assert.ok(deferredPayload.tasks.every((task) => task.status === 'open' && (task as Record<string, unknown>).defer_count as number >= 1));
  assert.equal(deferredPayload.truncated, true);
  assert.equal(deferredPayload.truncated, deferredPayload.total_matching > deferredPayload.count);

  const todaysResult = await harness.client.callTool({
    name: 'get_todays_tasks',
    arguments: {
      limit_per_bucket: 5,
    },
  });
  const todaysPayload = parseJsonContent<{
    limit_per_bucket: number;
    total_matching: number;
    returned: number;
    any_truncated: boolean;
    overdue: Array<{ id: string }>;
    today_tasks: Array<{ id: string }>;
    high_priority_undated: Array<{ id: string }>;
    truncated: {
      overdue: boolean;
      today_tasks: boolean;
      high_priority_undated: boolean;
    };
    summary: {
      overdue_count: number;
      overdue_returned: number;
      today_pool_count: number;
      today_tasks_returned: number;
      high_priority_undated_count: number;
      high_priority_undated_returned: number;
      total_matching: number;
      count: number;
    };
  }>(todaysResult);
  assert.equal(todaysPayload.limit_per_bucket, 5);
  assert.equal(todaysPayload.overdue.length, 5);
  assert.equal(todaysPayload.today_tasks.length, 5);
  assert.equal(todaysPayload.returned, todaysPayload.summary.count);
  assert.equal(todaysPayload.total_matching, todaysPayload.summary.total_matching);
  assert.equal(todaysPayload.any_truncated, true);
  assert.equal(todaysPayload.summary.overdue_returned, todaysPayload.overdue.length);
  assert.equal(todaysPayload.summary.today_tasks_returned, todaysPayload.today_tasks.length);
  assert.equal(
    todaysPayload.summary.high_priority_undated_returned,
    todaysPayload.high_priority_undated.length,
  );
  assert.equal(
    todaysPayload.truncated.overdue,
    todaysPayload.summary.overdue_count > todaysPayload.overdue.length,
  );
  assert.equal(
    todaysPayload.truncated.today_tasks,
    todaysPayload.summary.today_pool_count > todaysPayload.today_tasks.length,
  );
  assert.equal(
    todaysPayload.truncated.high_priority_undated,
    todaysPayload.summary.high_priority_undated_count > todaysPayload.high_priority_undated.length,
  );
  assert.equal(todaysPayload.summary.total_matching, (
    todaysPayload.summary.overdue_count
    + todaysPayload.summary.today_pool_count
    + todaysPayload.summary.high_priority_undated_count
  ));
  assert.equal(todaysPayload.summary.count, (
    todaysPayload.overdue.length
    + todaysPayload.today_tasks.length
    + todaysPayload.high_priority_undated.length
  ));

  const upcomingResult = await harness.client.callTool({
    name: 'get_upcoming_tasks',
    arguments: {
      days: 2,
      limit: 8,
    },
  });
  const upcomingPayload = parseJsonContent<{
    days_requested: number;
    limit: number;
    returned: number;
    total_matching: number;
    total_tasks: number;
    truncated: boolean;
    by_date: Record<string, Array<{ id: string }>>;
    day_counts: Record<string, number>;
  }>(upcomingResult);
  assert.equal(upcomingPayload.days_requested, 2);
  assert.equal(upcomingPayload.limit, 8);
  assert.equal(upcomingPayload.returned, 8);
  assert.equal(upcomingPayload.total_tasks, 8);
  assert.equal(upcomingPayload.truncated, true);
  assert.equal(upcomingPayload.truncated, upcomingPayload.total_matching > upcomingPayload.total_tasks);

  const dayCountTotal = Object.values(upcomingPayload.day_counts).reduce((sum, n) => sum + n, 0);
  assert.equal(dayCountTotal, upcomingPayload.total_tasks);
  for (const [date, count] of Object.entries(upcomingPayload.day_counts)) {
    assert.equal(upcomingPayload.by_date[date]?.length ?? 0, count);
  }
});
