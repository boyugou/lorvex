import assert from 'node:assert/strict';
import test from 'node:test';

import {
  asToolResultPayload,
  createHarness,
  parseJsonContent,
  parseTaskEnvelope,
  requireArrayItem,
} from '../shared';

test('set_task_reminders replaces pending reminders', async (t) => {
  const harness = await createHarness('set-reminders-basic');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  // Create task with initial reminders
  const createResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Task with reminders',
      reminders: ['2026-04-01T09:00:00Z'],
    },
  });
  const task = parseTaskEnvelope<{
    id: string;
    reminders: Array<{ reminder_at: string }>;
  }>(createResult);
  assert.equal(task.reminders.length, 1, 'Should have 1 initial reminder');

  // Replace with new reminders
  const setResult = await client.callTool({
    name: 'set_task_reminders',
    arguments: {
      id: task.id,
      reminders: ['2026-04-02T10:00:00Z', '2026-04-03T14:00:00Z'],
    },
  });
  const updated = parseJsonContent<{
    id: string;
    reminders: Array<{ reminder_at: string }>;
  }>(setResult);

  assert.equal(updated.reminders.length, 2, 'Should have 2 reminders after replacement');
  const times = updated.reminders.map(r => r.reminder_at).sort();
  assert.ok(
    requireArrayItem(times, 0, 'expected first reminder time').includes('2026-04-02'),
    'First reminder should be April 2',
  );
  assert.ok(
    requireArrayItem(times, 1, 'expected second reminder time').includes('2026-04-03'),
    'Second reminder should be April 3',
  );
});

test('set_task_reminders with empty array clears all reminders', async (t) => {
  const harness = await createHarness('set-reminders-clear');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Task to clear reminders',
      reminders: ['2026-04-01T09:00:00Z', '2026-04-02T09:00:00Z'],
    },
  });
  const task = parseTaskEnvelope<{
    id: string;
    reminders: Array<{ reminder_at: string }>;
  }>(createResult);
  assert.equal(task.reminders.length, 2, 'Should start with 2 reminders');

  const setResult = await client.callTool({
    name: 'set_task_reminders',
    arguments: { id: task.id, reminders: [] },
  });
  const cleared = parseJsonContent<{
    id: string;
    reminders: Array<{ reminder_at: string }>;
  }>(setResult);

  assert.equal(cleared.reminders.length, 0, 'Should have no reminders after clearing');
});

test('add_task_reminder appends without replacing existing reminders', async (t) => {
  const harness = await createHarness('add-reminder-append');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Task for add_task_reminder',
      reminders: ['2026-04-01T09:00:00Z'],
    },
  });
  const task = parseTaskEnvelope<{
    id: string;
    reminders: Array<{ reminder_at: string }>;
  }>(createResult);
  assert.equal(task.reminders.length, 1, 'Should start with 1 reminder');

  // Append a second reminder without replacing
  const addResult = await client.callTool({
    name: 'add_task_reminder',
    arguments: {
      id: task.id,
      reminder_at: '2026-04-05T14:00:00Z',
    },
  });
  const updated = parseJsonContent<{
    id: string;
    reminders: Array<{ reminder_at: string }>;
  }>(addResult);

  assert.equal(updated.reminders.length, 2, 'Should have 2 reminders after append');
  const times = updated.reminders.map(r => r.reminder_at).sort();
  assert.ok(
    requireArrayItem(times, 0, 'expected original reminder time').includes('2026-04-01'),
    'Original reminder should still be present',
  );
  assert.ok(
    requireArrayItem(times, 1, 'expected appended reminder time').includes('2026-04-05'),
    'New reminder should be appended',
  );
});

test('add_task_reminder rejects invalid timestamp', async (t) => {
  const harness = await createHarness('add-reminder-invalid');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Task for bad reminder' },
  });
  const task = parseTaskEnvelope<{ id: string }>(createResult);

  const addResult = await client.callTool({
    name: 'add_task_reminder',
    arguments: {
      id: task.id,
      reminder_at: 'not-a-date',
    },
  });
  const payload = asToolResultPayload(addResult);
  assert.equal(payload.isError, true, 'invalid reminder timestamp should be reported as an MCP error');
  const error = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(addResult);
  assert.equal(error.kind, 'validation');
  assert.match(error.message, /RFC 3339|ISO 8601|timestamp/i);
  assert.equal(error.retryable, false);
});

test('set_task_reminders returns enriched task with reminders array', async (t) => {
  const harness = await createHarness('set-reminders-enriched');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Enriched return test' },
  });
  const task = parseTaskEnvelope<{ id: string }>(createResult);

  const setResult = await client.callTool({
    name: 'set_task_reminders',
    arguments: {
      id: task.id,
      reminders: ['2026-05-01T08:00:00Z'],
    },
  });
  const updated = parseJsonContent<{
    id: string;
    reminders: Array<{ reminder_at: string; id: string }>;
  }>(setResult);

  assert.equal(updated.reminders.length, 1, 'Should have 1 reminder');
  const reminder = requireArrayItem(updated.reminders, 0, 'expected reminder row');
  assert.ok(reminder.id, 'Reminder should have an id');
  assert.ok(reminder.reminder_at.includes('2026-05-01'), 'Reminder time should match');
});
