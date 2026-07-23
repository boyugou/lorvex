import assert from 'node:assert/strict';
import test from 'node:test';

import { createHarness, parseJsonContent, parseTaskEnvelope } from '../shared';

test('update_task clears nullable text fields via null', async (t) => {
  const harness = await createHarness('update-task-clear-text-fields');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Nullable fields test',
      body: 'Some detailed body',
      due_date: '2026-04-01',
      due_time: '14:30',
      ai_notes: 'AI observation here',
    },
  });
  const created = parseTaskEnvelope<{
    id: string;
    body: string | null;
    due_date: string | null;
    due_time: string | null;
    ai_notes: string | null;
  }>(createResult);
  assert.equal(created.body, 'Some detailed body');
  assert.equal(created.due_date, '2026-04-01');
  assert.equal(created.due_time, '14:30');
  assert.equal(created.ai_notes, 'AI observation here');

  const clearResult1 = await client.callTool({
    name: 'update_task',
    arguments: { id: created.id, body: null, due_date: null, due_time: null },
  });
  const cleared1 = parseJsonContent<{
    id: string;
    body: string | null;
    due_date: string | null;
    due_time: string | null;
    ai_notes: string | null;
  }>(clearResult1);
  assert.equal(cleared1.body, null, 'body should be null after clearing');
  assert.equal(cleared1.due_date, null, 'due_date should be null after clearing');
  assert.equal(cleared1.due_time, null, 'due_time should be null when due_date is cleared');
  assert.equal(cleared1.ai_notes, 'AI observation here', 'ai_notes should be unchanged');

  const clearResult2 = await client.callTool({
    name: 'update_task',
    arguments: { id: created.id, ai_notes: null },
  });
  const cleared2 = parseJsonContent<{
    id: string;
    body: string | null;
    due_date: string | null;
    due_time: string | null;
    ai_notes: string | null;
  }>(clearResult2);
  assert.equal(cleared2.body, null, 'body should still be null');
  assert.equal(cleared2.due_date, null, 'due_date should still be null');
  assert.equal(cleared2.due_time, null, 'due_time should be null after clearing');
  assert.equal(cleared2.ai_notes, null, 'ai_notes should be null after clearing');
});

test('batch_update_tasks clears nullable fields via null', async (t) => {
  const harness = await createHarness('batch-update-clear-fields');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const taskAResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Batch A', body: 'body-a', due_date: '2026-05-01' },
  });
  const taskA = parseTaskEnvelope<{ id: string }>(taskAResult);

  const taskBResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Batch B', body: 'body-b', due_date: '2026-05-02' },
  });
  const taskB = parseTaskEnvelope<{ id: string }>(taskBResult);

  const batchResult = await client.callTool({
    name: 'batch_update_tasks',
    arguments: {
      updates: [
        { id: taskA.id, body: null },
        { id: taskB.id, body: null },
      ],
    },
  });
  const batch = parseJsonContent<{
    updated_count: number;
    tasks: Array<{ id: string; body: string | null; due_date: string | null }>;
  }>(batchResult);
  assert.equal(batch.updated_count, 2);
  for (const task of batch.tasks) {
    assert.equal(task.body, null, `body should be null for task ${task.id}`);
    assert.ok(task.due_date, `due_date should be preserved for task ${task.id}`);
  }
});
