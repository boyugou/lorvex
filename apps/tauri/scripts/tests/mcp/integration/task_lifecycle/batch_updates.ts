import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  createHarness,
  daysFromTodayYmd,
  parseJsonContent,
  parseTaskEnvelope,
  requireArrayItem,
} from '../shared';

test('batch_update_tasks spawns recurrence and propagates dependency changes on completion', async (t) => {
  const harness = await createHarness('batch-update-complete');
  t.after(async () => {
    await harness.cleanup();
  });

  const today = daysFromTodayYmd(0);
  const tomorrow = daysFromTodayYmd(1);

  const recurringResult = await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Weekly review',
      due_date: today,
      recurrence: { freq: 'weekly', interval: 1 },
    },
  });
  const recurringTask = parseTaskEnvelope<{ id: string; title: string; status: string }>(recurringResult);
  assert.equal(recurringTask.status, 'open');

  const dependentResult = await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Process review notes',
      due_date: tomorrow,
      depends_on: [recurringTask.id],
    },
  });
  const dependentTask = parseTaskEnvelope<{ id: string; title: string; depends_on: string | null }>(dependentResult);
  assert.ok(dependentTask.id);

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const beforeDependent = db.prepare('SELECT id FROM tasks WHERE id = ?')
    .get(dependentTask.id) as { id: string } | undefined;
  assert.ok(beforeDependent, 'Dependent task should exist before batch update');

  const batchResult = await harness.client.callTool({
    name: 'batch_update_tasks',
    arguments: {
      updates: [
        { id: recurringTask.id, status: 'completed' },
      ],
    },
  });
  const batchPayload = parseJsonContent<{
    updated_count: number;
    tasks: Array<{ id: string; status: string }>;
  }>(batchResult);
  assert.equal(batchPayload.updated_count, 1);
  assert.equal(
    requireArrayItem(batchPayload.tasks, 0, 'expected updated recurring task').status,
    'completed',
  );

  const allTasks = db.prepare(
    "SELECT id, title, status, recurrence, due_date FROM tasks WHERE title = 'Weekly review' ORDER BY created_at ASC",
  ).all() as Array<{ id: string; title: string; status: string; recurrence: string | null; due_date: string | null }>;

  assert.ok(allTasks.length >= 2, `Expected at least 2 tasks with title 'Weekly review' (original + recurrence spawn), got ${allTasks.length}`);
  const originalTask = allTasks.find((task) => task.id === recurringTask.id);
  assert.ok(originalTask, 'Original recurring task should still exist');
  assert.equal(originalTask.status, 'completed');

  const spawnedTask = allTasks.find((task) => task.id !== recurringTask.id && task.status === 'open');
  assert.ok(spawnedTask, 'Expected a new open task spawned from recurrence');
  assert.ok(spawnedTask.recurrence, 'Spawned task should inherit recurrence rule');
  assert.ok(spawnedTask.due_date, 'Spawned task should have a due date');
  assert.ok(spawnedTask.due_date > today, `Spawned task due_date (${spawnedTask.due_date}) should be after today (${today})`);

  const afterDependent = db.prepare('SELECT id FROM tasks WHERE id = ?')
    .get(dependentTask.id) as { id: string } | undefined;
  assert.ok(afterDependent, 'Dependent task should still exist after batch update');

  const dependentSyncEvent = db.prepare(`
    SELECT entity_id, operation
    FROM sync_outbox
    WHERE entity_id = ?
    ORDER BY created_at DESC
    LIMIT 1
  `).get(dependentTask.id) as { entity_id: string; operation: string } | undefined;
  assert.ok(dependentSyncEvent, 'Expected sync_event for dependent task after dependency propagation');
  assert.equal(dependentSyncEvent.operation, 'upsert');
});

test('batch_update_tasks propagates depends_on changes', async (t) => {
  const harness = await createHarness('batch-update-deps');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const taskAResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Task A' },
  });
  const taskA = parseTaskEnvelope<{ id: string }>(taskAResult);

  const taskBResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Task B' },
  });
  const taskB = parseTaskEnvelope<{ id: string }>(taskBResult);

  const updateResult = await client.callTool({
    name: 'batch_update_tasks',
    arguments: {
      updates: [
        { id: taskB.id, depends_on: [taskA.id] },
      ],
    },
  });
  const updatePayload = parseJsonContent<{
    updated_count: number;
    tasks: Array<{ id: string; depends_on: string[] | null }>;
  }>(updateResult);
  assert.equal(updatePayload.updated_count, 1);
  const updatedB = requireArrayItem(updatePayload.tasks, 0, 'expected updated dependency task');
  const bDeps = updatedB.depends_on ?? [];
  assert.ok(bDeps.includes(taskA.id), 'Task B depends_on should contain Task A');

  const update2Result = await client.callTool({
    name: 'batch_update_tasks',
    arguments: {
      updates: [
        { id: taskA.id, body: null },
      ],
    },
  });
  const update2Payload = parseJsonContent<{
    updated_count: number;
    tasks: Array<{ id: string; body: string | null }>;
  }>(update2Result);
  assert.equal(update2Payload.updated_count, 1);
  const updatedA = requireArrayItem(update2Payload.tasks, 0, 'expected updated nullability task');
  assert.equal(updatedA.body, null, 'body should be null after setting to null');
});
