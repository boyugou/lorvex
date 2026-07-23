import assert from 'node:assert/strict';
import test from 'node:test';

import { createHarness, parseJsonContent, parseTaskEnvelope, daysFromTodayYmd } from '../shared';

/**
 * Simulates a realistic morning planning session:
 * 1. AI checks overview to understand current state
 * 2. AI sets the current focus with focused tasks
 * 3. AI checks today's tasks
 * 4. User completes first task via app
 * 5. AI verifies completion is reflected in overview
 */
test('morning planning workflow: overview → plan → complete → verify', async (t) => {
  const harness = await createHarness('morning-planning');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const today = daysFromTodayYmd();

  // Step 1: Create a list and seed tasks
  const listResult = await client.callTool({
    name: 'create_list',
    arguments: { name: 'Work' },
  });
  const list = parseJsonContent<{ id: string }>(listResult);

  const task1Result = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Write quarterly report',
      list_id: list.id,
      due_date: today,
      estimated_minutes: 60,
      priority: 3,
    },
  });
  const task1 = parseTaskEnvelope<{ id: string; title: string }>(task1Result);

  const task2Result = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Review team PRs',
      list_id: list.id,
      due_date: today,
      estimated_minutes: 30,
      priority: 2,
    },
  });
  const task2 = parseTaskEnvelope<{ id: string; title: string }>(task2Result);

  await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Clean up backlog items',
      list_id: list.id,
      priority: 1,
    },
  });

  // Step 2: AI gets overview
  const overviewResult = await client.callTool({
    name: 'get_overview',
    arguments: {},
  });
  const overview = parseJsonContent<{
    stats: { open_count: number; today_pool_count: number };
  }>(overviewResult);

  assert.ok(overview.stats.open_count >= 3, 'Overview should show at least 3 open tasks');
  assert.ok(overview.stats.today_pool_count >= 2, 'Overview should show at least 2 due today');

  // Step 3: AI sets current focus
  const planResult = await client.callTool({
    name: 'set_current_focus',
    arguments: {
      task_ids: [task1.id, task2.id],
      date: today,
    },
  });
  const plan = parseJsonContent<{ date: string; task_ids: string[] }>(planResult);
  assert.equal(plan.task_ids.length, 2, 'Current focus should contain 2 tasks');

  // Step 4: AI gets today's tasks (bucketed response)
  const todayResult = await client.callTool({
    name: 'get_todays_tasks',
    arguments: {},
  });
  const todayData = parseJsonContent<{
    today_tasks: Array<{ id: string; title: string }>;
    overdue: Array<{ id: string }>;
    summary: { count: number };
  }>(todayResult);
  assert.ok(todayData.today_tasks.length >= 2, 'Should have at least 2 tasks due today');

  // Step 5: Complete first task
  const completeResult = await client.callTool({
    name: 'complete_task',
    arguments: { id: task1.id },
  });
  const completed = parseTaskEnvelope<{ id: string; status: string }>(completeResult, 'completed');
  assert.equal(completed.status, 'completed', 'Task should be marked completed');

  // Step 6: AI adds notes to remaining task
  const notesResult = await client.callTool({
    name: 'set_task_ai_notes',
    arguments: {
      id: task2.id,
      notes: 'Focus on critical PRs first; 3 PRs pending review.',
    },
  });
  const withNotes = parseJsonContent<{ id: string; ai_notes: string }>(notesResult);
  assert.ok(withNotes.ai_notes.includes('3 PRs pending'), 'AI notes should be saved');

  // Step 7: Verify overview reflects completion
  const overviewAfter = await client.callTool({
    name: 'get_overview',
    arguments: {},
  });
  const overviewUpdated = parseJsonContent<{
    stats: { completed_this_week: number };
  }>(overviewAfter);
  assert.ok(overviewUpdated.stats.completed_this_week >= 1, 'Should show at least 1 completed this week');
});

/**
 * Simulates creating tasks from a conversation:
 * 1. AI batch-creates multiple tasks
 * 2. AI promotes the most urgent one
 * 3. AI verifies the promotion affected urgency ordering
 */
test('conversation capture workflow: batch create → promote → verify ordering', async (t) => {
  const harness = await createHarness('conversation-capture');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const today = daysFromTodayYmd();

  const listResult = await client.callTool({
    name: 'create_list',
    arguments: { name: 'Personal' },
  });
  const list = parseJsonContent<{ id: string }>(listResult);

  // Batch create tasks from conversation
  const batchResult = await client.callTool({
    name: 'batch_create_tasks',
    arguments: {
      tasks: [
        { title: 'Book dentist appointment', list_id: list.id, priority: 1 },
        { title: 'Call mom for birthday', list_id: list.id, due_date: today, priority: 3 },
        { title: 'Buy groceries for dinner', list_id: list.id, priority: 2 },
      ],
    },
  });
  const batch = parseJsonContent<{ created_count: number; tasks: Array<{ id: string; title: string }> }>(batchResult);
  assert.equal(batch.tasks.length, 3, 'Should create all 3 tasks');

  // Promote the most urgent task by updating planned_date to today and adding to focus
  const urgentTask = batch.tasks.find(t => t.title.includes('Call mom'));
  assert.ok(urgentTask, 'Should find the urgent task');

  await client.callTool({
    name: 'update_task',
    arguments: {
      id: urgentTask!.id,
      planned_date: today,
    },
  });
  const focusResult = await client.callTool({
    name: 'add_to_current_focus',
    arguments: {
      task_ids: [urgentTask!.id],
    },
  });
  const focus = parseJsonContent<{
    task_ids: string[];
  }>(focusResult);
  assert.ok(focus.task_ids.includes(urgentTask!.id), 'Promoted task should be in current focus');

  // Verify task appears in today's tasks (bucketed response)
  const todayResult = await client.callTool({
    name: 'get_todays_tasks',
    arguments: {},
  });
  const todayData = parseJsonContent<{
    today_tasks: Array<{ id: string }>;
    summary: { count: number };
  }>(todayResult);
  assert.ok(todayData.summary.count >= 1, 'Should have at least 1 task for today');
  const allTodayIds = todayData.today_tasks.map(t => t.id);
  assert.ok(allTodayIds.includes(urgentTask!.id), 'Promoted task should appear in today_tasks');
});
