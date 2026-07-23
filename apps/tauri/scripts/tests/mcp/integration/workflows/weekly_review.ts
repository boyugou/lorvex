import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  createHarness,
  insertListSeed,
  insertTaskSeed,
  isoDaysAgo,
  daysFromTodayYmd,
  parseJsonContent,
} from '../shared';

/**
 * Simulates the weekly review workflow:
 * 1. Seed data: completed tasks, overdue tasks, stalled lists, frequently-deferred tasks
 * 2. AI gets weekly review snapshot
 * 3. AI identifies stalled list and archives it
 * 4. AI reschedules a frequently-deferred task
 * 5. Verify changes are reflected
 *
 * Note: The weekly review snapshot uses these queries:
 * - top_stalled_lists: lists where all open tasks have last_activity older than 7 days
 * - top_deferred: tasks with status='open' AND defer_count >= 3
 */
test('weekly review workflow: snapshot → stalled list archive → defer intervention', async (t) => {
  const harness = await createHarness('weekly-review');
  t.after(async () => { await harness.cleanup(); });
  const { client, dbPath } = harness;

  const today = daysFromTodayYmd();
  const db = new Database(dbPath);
  const stalledTaskId = '01966a3f-7c8b-7d4e-8f3a-000000000301';
  const deferredTaskId = '01966a3f-7c8b-7d4e-8f3a-000000000302';
  const completedTaskId = '01966a3f-7c8b-7d4e-8f3a-000000000303';

  // Seed: a list with stalled tasks (no activity for 14+ days)
  const stalledListId = '01966a3f-7c8b-7d4e-8f3a-000000000701';
  insertListSeed(db, { id: stalledListId, name: 'Stalled Project' });

  insertTaskSeed(db, {
    id: stalledTaskId,
    title: 'Old stalled task',
    list_id: stalledListId,
    status: 'open',
    created_at: isoDaysAgo(30),
    updated_at: isoDaysAgo(20),
  });

  // Seed: a frequently deferred task (status must be 'open' with defer_count >= 3)
  const activeListId = '01966a3f-7c8b-7d4e-8f3a-000000000702';
  insertListSeed(db, { id: activeListId, name: 'Active Work' });

  insertTaskSeed(db, {
    id: deferredTaskId,
    title: 'Procrastinated task',
    list_id: activeListId,
    status: 'open',
    defer_count: 5,
    created_at: isoDaysAgo(21),
    updated_at: isoDaysAgo(1),
  });

  // Seed: a completed task this week
  insertTaskSeed(db, {
    id: completedTaskId,
    title: 'Done task',
    list_id: activeListId,
    status: 'completed',
    created_at: isoDaysAgo(7),
    updated_at: isoDaysAgo(1),
  });
  // Mark completed_at separately since insertTaskSeed doesn't support it
  db.prepare('UPDATE tasks SET completed_at = ? WHERE id = ?').run(isoDaysAgo(1), completedTaskId);

  db.close();

  // Step 1: Get weekly review snapshot
  const reviewResult = await client.callTool({
    name: 'get_weekly_review_snapshot',
    arguments: {},
  });
  const review = parseJsonContent<{
    counts: {
      completed_this_week: number;
      created_this_week: number;
      overdue_open: number;
      deferred_open: number;
      someday: number;
    };
    top_completed: Array<{ id: string; title: string }>;
    top_stalled_lists: Array<{ id: string; name: string; open_task_count: number }>;
    top_deferred: Array<{ id: string; title: string; defer_count: number }>;
  }>(reviewResult);

  assert.ok(review.counts.completed_this_week >= 1, 'Should have completed tasks this week');
  assert.ok(review.top_stalled_lists.length >= 1, 'Should detect stalled list');
  assert.ok(review.counts.deferred_open >= 1, 'Should detect frequently deferred tasks');

  // Step 2: Archive the stalled list (batch cancel all tasks)
  const stalledList = review.top_stalled_lists.find(p => p.name === 'Stalled Project');
  assert.ok(stalledList, 'Should find the stalled list');

  const archiveResult = await client.callTool({
    name: 'batch_cancel_tasks_in_list',
    arguments: {
      list_id: stalledList!.id,
      statuses: ['open'],
    },
  });
  const archived = parseJsonContent<{ cancelled_count: number }>(archiveResult);
  assert.ok(archived.cancelled_count >= 1, 'Should cancel at least 1 task');

  // Step 3: Reschedule the frequently deferred task
  const deferredTask = review.top_deferred.find(t => t.title === 'Procrastinated task');
  assert.ok(deferredTask, 'Should find deferred task in top_deferred');

  const rescheduleResult = await client.callTool({
    name: 'update_task',
    arguments: {
      id: deferredTask!.id,
      due_date: today,
      estimated_minutes: 30,
    },
  });
  const rescheduled = parseJsonContent<{
    id: string;
    status: string;
    due_date: string;
  }>(rescheduleResult);
  assert.equal(rescheduled.status, 'open', 'Rescheduled task should be open');
  assert.equal(rescheduled.due_date, today, 'Rescheduled task should be due today');

  // Step 4: Verify it shows up in today's tasks (bucketed response)
  const todayResult = await client.callTool({
    name: 'get_todays_tasks',
    arguments: {},
  });
  const todayData = parseJsonContent<{
    today_tasks: Array<{ id: string }>;
    overdue: Array<{ id: string }>;
    high_priority_undated: Array<{ id: string }>;
  }>(todayResult);
  const allTodayIds = [
    ...todayData.today_tasks,
    ...todayData.overdue,
    ...todayData.high_priority_undated,
  ].map(t => t.id);
  assert.ok(allTodayIds.includes(deferredTask!.id), 'Rescheduled deferred task should appear in today view');
});
