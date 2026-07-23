import assert from 'node:assert/strict';
import test from 'node:test';

import {
  asToolResultPayload,
  createHarness,
  getFirstTextContent,
  parseJsonContent,
  parseTaskEnvelope,
} from '../shared';
import { daysFromTodayYmd as daysFromToday } from '../shared/time';

test('defer_task keeps status open, sets planned_date, and increments defer_count', async (t) => {
  const harness = await createHarness('defer-task-basic');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Task to defer' },
  });
  const task = parseTaskEnvelope<{ id: string; defer_count: number }>(createResult);
  assert.equal(task.defer_count, 0, 'Initial defer_count should be 0');

  const target = daysFromToday(3);
  const deferResult = await client.callTool({
    name: 'defer_task',
    arguments: { id: task.id, until_date: target, reason: 'Not ready yet' },
  });
  const deferred = parseJsonContent<{
    id: string;
    status: string;
    planned_date: string | null;
    defer_count: number;
    last_deferred_at: string | null;
    ai_notes: string | null;
  }>(deferResult);

  assert.equal(deferred.status, 'open', 'Status should remain open after deferral');
  assert.equal(deferred.defer_count, 1, 'defer_count should increment to 1');
  assert.equal(deferred.planned_date, target, 'planned_date should match until_date');
  assert.ok(deferred.last_deferred_at, 'last_deferred_at should be set');
  assert.ok(
    deferred.ai_notes?.includes('Not ready yet'),
    `ai_notes should contain reason, got: ${deferred.ai_notes}`,
  );
});

test('defer_task sets planned_date to the absolute until_date', async (t) => {
  const harness = await createHarness('defer-task-absolute');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Task with due date', due_date: '2099-01-15' },
  });
  const task = parseTaskEnvelope<{ id: string; due_date: string | null }>(createResult);

  const target = daysFromToday(7);
  const deferResult = await client.callTool({
    name: 'defer_task',
    arguments: { id: task.id, until_date: target },
  });
  const deferred = parseJsonContent<{
    id: string;
    status: string;
    planned_date: string | null;
    defer_count: number;
  }>(deferResult);

  assert.equal(deferred.status, 'open', 'Status should remain open after deferral');
  assert.equal(deferred.defer_count, 1);
  assert.equal(deferred.planned_date, target, 'planned_date should equal until_date');
});

test('defer_task increments defer_count across repeated deferrals', async (t) => {
  const harness = await createHarness('defer-task-repeat');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Repeatedly deferred' },
  });
  const task = parseTaskEnvelope<{ id: string }>(createResult);

  for (let i = 1; i <= 3; i += 1) {
    const deferResult = await client.callTool({
      name: 'defer_task',
      arguments: { id: task.id, until_date: daysFromToday(i) },
    });
    const deferred = parseJsonContent<{ defer_count: number }>(deferResult);
    assert.equal(deferred.defer_count, i, `defer_count should equal ${i}`);
  }
});

test('defer_task rejects completed tasks', async (t) => {
  const harness = await createHarness('defer-task-reject-completed');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Already done' },
  });
  const task = parseTaskEnvelope<{ id: string }>(createResult);

  await client.callTool({
    name: 'complete_task',
    arguments: { id: task.id },
  });

  const deferResult = await client.callTool({
    name: 'defer_task',
    arguments: { id: task.id, until_date: daysFromToday(1) },
  });
  const payload = asToolResultPayload(deferResult);
  assert.equal(payload.isError, true, 'deferring a completed task should be reported as an MCP error');
  const error = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(deferResult);
  assert.equal(error.kind, 'validation');
  assert.match(error.message, /Cannot defer a task with status 'completed'/);
  assert.equal(error.retryable, false);
});

test('defer_task rejects malformed until_date', async (t) => {
  const harness = await createHarness('defer-task-bad-date');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const createResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Bad date test' },
  });
  const task = parseTaskEnvelope<{ id: string }>(createResult);

  const result = asToolResultPayload(await client.callTool({
    name: 'defer_task',
    arguments: { id: task.id, until_date: 'not-a-date' },
  }));
  const text = getFirstTextContent(result);
  assert.ok(
    result.isError === true || /error|invalid|date|parse/i.test(text),
    `Should reject malformed until_date, got isError=${result.isError} text=${text}`,
  );
});
