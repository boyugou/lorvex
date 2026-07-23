import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import { createHarness, daysFromTodayYmd, parseJsonContent, parseTaskEnvelope, requireArrayItem } from '../shared';

test('focus schedule and review workflow tools preserve rich direct MCP contracts', async (t) => {
  const harness = await createHarness('workflow-focus-and-review');
  t.after(async () => {
    await harness.cleanup();
  });

  const { client } = harness;
  const date = daysFromTodayYmd();

  const linkedList = parseJsonContent<{ id: string }>(await client.callTool({
    name: 'create_list',
    arguments: { name: 'Focus Review List' },
  }));

  const createTask = async (title: string) =>
    parseTaskEnvelope<{ id: string }>(await client.callTool({
      name: 'create_task',
      arguments: {
        title,
        list_id: linkedList.id,
        due_date: date,
      },
    }));

  const [taskA, taskB] = await Promise.all([
    createTask('Focus review task A'),
    createTask('Focus review task B'),
  ]);

  const emptySchedule = parseJsonContent<{
    date: string;
    schedule: null;
    message: string;
  }>(await client.callTool({
    name: 'get_saved_focus_schedule',
    arguments: {
      date: '2099-01-01',
    },
  }));
  assert.equal(emptySchedule.date, '2099-01-01');
  assert.equal(emptySchedule.schedule, null);
  assert.match(emptySchedule.message, /No saved focus schedule found for 2099-01-01/);

  const emptyHistory = parseJsonContent<{ reviews: unknown[] }>(await client.callTool({
    name: 'get_review_history',
    arguments: {
      limit: 5,
    },
  }));
  assert.deepEqual(emptyHistory.reviews, []);

  const savedSchedule = parseJsonContent<{
    date: string;
    rationale: string | null;
    blocks: Array<{ block_type: string; task_id: string | null; start_time: number | string; end_time: number | string }>;
    task_ids_applied: string[];
  }>(await client.callTool({
    name: 'save_focus_schedule',
    arguments: {
      date,
      rationale: 'Protect the highest-value morning work first.',
      blocks: [
        {
          task_id: taskA.id,
          start_time: '09:00',
          end_time: '09:45',
          block_type: 'task',
        },
        {
          task_id: null,
          start_time: '09:45',
          end_time: '10:00',
          block_type: 'buffer',
        },
        {
          task_id: null,
          start_time: '10:00',
          end_time: '10:30',
          block_type: 'buffer',
        },
        {
          task_id: taskB.id,
          start_time: '10:30',
          end_time: '11:00',
          block_type: 'task',
        },
      ],
    },
  }));
  assert.equal(savedSchedule.date, date);
  assert.equal(savedSchedule.rationale, 'Protect the highest-value morning work first.');
  assert.equal(savedSchedule.blocks.length, 4);
  assert.deepEqual(savedSchedule.task_ids_applied, [taskA.id, taskB.id]);

  const fetchedSchedule = parseJsonContent<{
    date: string;
    blocks: Array<{ block_type: string; task_id: string | null }>;
  }>(await client.callTool({
    name: 'get_saved_focus_schedule',
    arguments: { date },
  }));
  assert.equal(fetchedSchedule.date, date);
  assert.equal(fetchedSchedule.blocks.length, 4);
  const bufferBlock = requireArrayItem(fetchedSchedule.blocks, 1, 'expected inserted buffer block');
  assert.equal(bufferBlock.block_type, 'buffer');
  assert.equal(bufferBlock.task_id, null);

  const afterRemoval = parseJsonContent<{
    date: string;
    task_ids: string[];
  }>(await client.callTool({
    name: 'remove_from_current_focus',
    arguments: {
      date,
      task_id: taskA.id,
    },
  }));
  assert.equal(afterRemoval.date, date);
  assert.deepEqual(afterRemoval.task_ids, [taskB.id]);

  const clearedFocus = parseJsonContent<{
    cleared: boolean;
    date: string;
    previous: { date: string; task_ids: string[] };
  }>(await client.callTool({
    name: 'clear_current_focus',
    arguments: { date },
  }));
  assert.equal(clearedFocus.cleared, true);
  assert.equal(clearedFocus.date, date);
  assert.equal(clearedFocus.previous.date, date);
  assert.deepEqual(clearedFocus.previous.task_ids, [taskB.id]);

  await client.callTool({
    name: 'set_current_focus',
    arguments: {
      date,
      task_ids: [taskA.id],
    },
  });
  const removedLastFocusTask = parseJsonContent<{
    removed: boolean;
    task_id: string;
    date: string;
    plan_cleared: boolean;
    remaining_tasks: number;
  }>(await client.callTool({
    name: 'remove_from_current_focus',
    arguments: {
      date,
      task_id: taskA.id,
    },
  }));
  assert.equal(removedLastFocusTask.removed, true);
  assert.equal(removedLastFocusTask.task_id, taskA.id);
  assert.equal(removedLastFocusTask.date, date);
  assert.equal(removedLastFocusTask.plan_cleared, true);
  assert.equal(removedLastFocusTask.remaining_tasks, 0);

  await client.callTool({
    name: 'add_daily_review',
    arguments: {
      date,
      summary: 'Strong focus and clean execution.',
      mood: 4,
      energy_level: 4,
      linked_task_ids: [taskA.id],
      linked_list_ids: [linkedList.id],
      wins: 'Locked the morning schedule.',
    },
  });

  const amendedReview = parseJsonContent<{
    date: string;
    summary: string;
    mood: number | null;
    linked_task_ids: string[];
    linked_list_ids: string[];
    blockers: string | null;
  }>(await client.callTool({
    name: 'amend_daily_review',
    arguments: {
      date,
      summary: 'Strong focus and deliberate replanning.',
      mood: 5,
      blockers: 'Only minor calendar churn.',
      linked_task_ids: [taskA.id, taskB.id],
      linked_list_ids: [linkedList.id],
    },
  }));
  assert.equal(amendedReview.date, date);
  assert.equal(amendedReview.summary, 'Strong focus and deliberate replanning.');
  assert.equal(amendedReview.mood, 5);
  assert.equal(amendedReview.blockers, 'Only minor calendar churn.');
  assert.deepEqual(amendedReview.linked_task_ids.sort(), [taskA.id, taskB.id].sort());
  assert.deepEqual(amendedReview.linked_list_ids, [linkedList.id]);

  const reviewHistory = parseJsonContent<{
    reviews: Array<{
      date: string;
      summary: string;
      linked_task_ids: string[];
    }>;
  }>(await client.callTool({
    name: 'get_review_history',
    arguments: {
      since: date,
      limit: 5,
    },
  }));
  assert.equal(reviewHistory.reviews.length, 1);
  const review = requireArrayItem(reviewHistory.reviews, 0, 'expected review history row');
  assert.equal(review.date, date);
  assert.equal(review.summary, 'Strong focus and deliberate replanning.');
  assert.deepEqual(review.linked_task_ids.sort(), [taskA.id, taskB.id].sort());

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const changelogRows = db.prepare(`
    SELECT DISTINCT mcp_tool
    FROM ai_changelog
    WHERE mcp_tool IN ('save_focus_schedule', 'remove_from_current_focus', 'clear_current_focus', 'add_daily_review', 'amend_daily_review')
  `).all() as Array<{ mcp_tool: string }>;
  assert.deepEqual(
    changelogRows.map((row) => row.mcp_tool).sort(),
    ['add_daily_review', 'amend_daily_review', 'clear_current_focus', 'remove_from_current_focus', 'save_focus_schedule'],
  );
});

test('memory, habit reminder, and tag admin tools return rich mutation payloads', async (t) => {
  const harness = await createHarness('workflow-admin-tools');
  t.after(async () => {
    await harness.cleanup();
  });

  const { client } = harness;

  const taggedTask = parseTaskEnvelope<{ id: string }>(await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Task with tag to rename',
      tags: ['UrgentOld'],
    },
  }));

  const renameTagResult = parseJsonContent<{
    old_name: string;
    new_name: string;
    tasks_updated: number;
    task_ids: string[];
  }>(await client.callTool({
    name: 'rename_tag',
    arguments: {
      old_name: 'UrgentOld',
      new_name: 'UrgentNew',
    },
  }));
  assert.equal(renameTagResult.old_name, 'UrgentOld');
  assert.equal(renameTagResult.new_name, 'UrgentNew');
  assert.equal(renameTagResult.tasks_updated, 1);
  assert.deepEqual(renameTagResult.task_ids, [taggedTask.id]);

  await client.callTool({
    name: 'write_memory',
    arguments: {
      key: 'workflow_admin_memory',
      content: 'Remember to audit workflow tool coverage in coherent batches.',
    },
  });
  const deletedMemory = parseJsonContent<{
    deleted: boolean;
    key: string;
    previous: { key: string; content: string };
  }>(await client.callTool({
    name: 'delete_memory',
    arguments: { key: 'workflow_admin_memory' },
  }));
  assert.equal(deletedMemory.deleted, true);
  assert.equal(deletedMemory.key, 'workflow_admin_memory');
  assert.equal(deletedMemory.previous.key, 'workflow_admin_memory');
  assert.match(deletedMemory.previous.content, /audit workflow tool coverage/);

  await client.callTool({
    name: 'set_preference',
    arguments: {
      key: 'dashboard_layout',
      value: { enabled: true, cadence: 'daily' },
    },
  });
  const deletedPreference = parseJsonContent<{
    deleted: boolean;
    key: string;
  }>(await client.callTool({
    name: 'delete_preference',
    arguments: { key: 'dashboard_layout' },
  }));
  assert.equal(deletedPreference.deleted, true);
  assert.equal(deletedPreference.key, 'dashboard_layout');
  const preferenceAfterDelete = parseJsonContent<null>(await client.callTool({
    name: 'get_preference',
    arguments: { key: 'dashboard_layout' },
  }));
  assert.equal(preferenceAfterDelete, null);

  const createdHabit = parseJsonContent<{ id: string; name: string }>(await client.callTool({
    name: 'create_habit',
    arguments: {
      name: 'Stretch',
      frequency_type: 'daily',
    },
  }));
  const reminderPolicy = parseJsonContent<{
    id: string;
    habit_id: string;
    habit_name: string;
    reminder_time: string;
  }>(await client.callTool({
    name: 'upsert_habit_reminder_policy',
    arguments: {
      habit_id: createdHabit.id,
      reminder_time: '08:30',
      enabled: true,
    },
  }));
  assert.equal(reminderPolicy.habit_id, createdHabit.id);
  assert.equal(reminderPolicy.habit_name, 'Stretch');
  assert.equal(reminderPolicy.reminder_time, '08:30');

  const deletedPolicy = parseJsonContent<{
    deleted: boolean;
    id: string;
    before: { id: string; habit_name: string; reminder_time: string };
  }>(await client.callTool({
    name: 'delete_habit_reminder_policy',
    arguments: {
      id: reminderPolicy.id,
    },
  }));
  assert.equal(deletedPolicy.deleted, true);
  assert.equal(deletedPolicy.id, reminderPolicy.id);
  assert.equal(deletedPolicy.before.id, reminderPolicy.id);
  assert.equal(deletedPolicy.before.habit_name, 'Stretch');
  assert.equal(deletedPolicy.before.reminder_time, '08:30');

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const renamedTagRow = db.prepare(`
    SELECT t.display_name AS display_name, tt.task_id AS task_id
    FROM tags t
    JOIN task_tags tt ON tt.tag_id = t.id
    WHERE t.lookup_key = 'urgentnew'
  `).get() as { display_name: string; task_id: string } | undefined;
  assert.ok(renamedTagRow, 'Expected renamed tag to remain linked to the task');
  assert.equal(renamedTagRow.display_name, 'UrgentNew');
  assert.equal(renamedTagRow.task_id, taggedTask.id);

  const deletedPolicyRow = db.prepare(
    'SELECT COUNT(*) AS count FROM habit_reminder_policies WHERE id = ?',
  ).get(reminderPolicy.id) as { count: number };
  assert.equal(deletedPolicyRow.count, 0, 'Expected delete_habit_reminder_policy to remove the row');

  const adminChangelogRows = db.prepare(`
    SELECT DISTINCT mcp_tool
    FROM ai_changelog
    WHERE mcp_tool IN ('rename_tag', 'delete_memory', 'delete_habit_reminder_policy', 'delete_preference')
  `).all() as Array<{ mcp_tool: string }>;
  assert.deepEqual(
    adminChangelogRows.map((row) => row.mcp_tool).sort(),
    ['delete_habit_reminder_policy', 'delete_memory', 'delete_preference', 'rename_tag'],
  );
});
