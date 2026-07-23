import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  asToolResultPayload,
  createHarness,
  parseJsonContent,
  parseTaskEnvelope,
  requireArrayItem,
} from '../shared';

test('batch_cancel_tasks_in_list cleans depends_on in other tasks', async (t) => {
  const harness = await createHarness('batch-cancel-deps');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const listResult = await client.callTool({
    name: 'create_list',
    arguments: { name: 'Cancel Test List' },
  });
  const list = parseJsonContent<{ id: string }>(listResult);

  const blockerResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Blocker task',
      list_id: list.id,
    },
  });
  const blockerTask = parseTaskEnvelope<{ id: string }>(blockerResult);

  const blockedResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Blocked task',
      depends_on: [blockerTask.id],
    },
  });
  const blockedTask = parseTaskEnvelope<{ id: string; depends_on: string[] | null }>(blockedResult);

  const parsedDeps = blockedTask.depends_on ?? [];
  assert.ok(parsedDeps.includes(blockerTask.id), 'Blocked task should depend on blocker');

  const cancelResult = await client.callTool({
    name: 'batch_cancel_tasks_in_list',
    arguments: { list_id: list.id },
  });
  const cancelData = parseJsonContent<{ cancelled_count: number }>(cancelResult);
  assert.equal(cancelData.cancelled_count, 1, 'Should have cancelled 1 task in the list');

  const db = new Database(harness.dbPath, { readonly: true });
  t.after(() => { db.close(); });

  const cancelledBlocker = db.prepare('SELECT status FROM tasks WHERE id = ?')
    .get(blockerTask.id) as { status: string } | undefined;
  assert.ok(cancelledBlocker, 'Blocker task should exist');
  assert.equal(cancelledBlocker.status, 'cancelled');

  const updatedDeps = db.prepare(
    'SELECT depends_on_task_id FROM task_dependencies WHERE task_id = ?'
  ).all(blockedTask.id) as { depends_on_task_id: string }[];
  const depIds = updatedDeps.map(r => r.depends_on_task_id);
  assert.ok(
    !depIds.includes(blockerTask.id),
    `Blocked task should no longer depend on cancelled blocker, got: ${JSON.stringify(depIds)}`,
  );
});

test('cancel_task cleans depends_on in dependent tasks', async (t) => {
  const harness = await createHarness('cancel-task-deps');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const blockerResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Single blocker' },
  });
  const blocker = parseTaskEnvelope<{ id: string }>(blockerResult);

  const blockedResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Depends on blocker',
      depends_on: [blocker.id],
    },
  });
  const blocked = parseTaskEnvelope<{ id: string; depends_on: string[] | null }>(blockedResult);
  const deps = blocked.depends_on ?? [];
  assert.ok(deps.includes(blocker.id), 'Blocked task should depend on blocker');

  const cancelResult = await client.callTool({
    name: 'cancel_task',
    arguments: { id: blocker.id, reason: 'No longer needed' },
  });
  const cancelPayload = parseJsonContent<{
    cancelled: { id: string; status: string };
    dependency_updates: Array<{ id: string }>;
  }>(cancelResult);
  assert.equal(cancelPayload.cancelled.status, 'cancelled');
  assert.ok(Array.isArray(cancelPayload.dependency_updates), 'should return dependency_updates array');

  const db = new Database(harness.dbPath, { readonly: true });
  t.after(() => { db.close(); });

  const blockedRow = db.prepare('SELECT id FROM tasks WHERE id = ?')
    .get(blocked.id) as { id: string } | undefined;
  assert.ok(blockedRow, 'Blocked task should still exist');

  const remainingDeps = db.prepare(
    'SELECT depends_on_task_id FROM task_dependencies WHERE task_id = ?'
  ).all(blocked.id) as { depends_on_task_id: string }[];
  const depIds = remainingDeps.map(r => r.depends_on_task_id);
  assert.ok(
    !depIds.includes(blocker.id),
    `depends_on should not contain cancelled task ID, got: ${JSON.stringify(depIds)}`,
  );

  const cancelledRow = db.prepare('SELECT ai_notes FROM tasks WHERE id = ?')
    .get(blocker.id) as { ai_notes: string | null } | undefined;
  assert.ok(cancelledRow, 'Cancelled task should exist');
  assert.ok(
    cancelledRow.ai_notes?.includes('No longer needed'),
    `ai_notes should contain cancel reason, got: ${cancelledRow.ai_notes}`,
  );
});

test('batch_cancel_tasks returns rich batch payloads, successor spawn, and dependency cleanup', async (t) => {
  const harness = await createHarness('batch-cancel-by-ids');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const listResult = await client.callTool({
    name: 'create_list',
    arguments: { name: 'Batch Cancel List' },
  });
  const list = parseJsonContent<{ id: string }>(listResult);

  const blockerResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Batch cancel blocker',
      list_id: list.id,
      body: 'Blocker body for rich payload coverage.',
    },
  });
  const blockerTask = parseTaskEnvelope<{ id: string; body: string | null }>(blockerResult);

  const blockedResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Batch cancel dependent',
      depends_on: [blockerTask.id],
    },
  });
  const blockedTask = parseTaskEnvelope<{ id: string }>(blockedResult);

  const recurringResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Recurring batch cancel task',
      list_id: list.id,
      body: 'Recurring task body for successor payload coverage.',
      recurrence: { freq: 'weekly', interval: 1 },
      reminders: ['2099-05-10T09:00:00Z'],
    },
  });
  const recurringTask = parseTaskEnvelope<{
    id: string;
    recurrence: string | null;
    body: string | null;
    list_id: string | null;
  }>(recurringResult);
  assert.equal(recurringTask.recurrence, '{"FREQ":"WEEKLY","INTERVAL":1}');

  const batchCancelResult = await client.callTool({
    name: 'batch_cancel_tasks',
    arguments: {
      task_ids: [blockerTask.id, recurringTask.id],
      reason: 'Batch cleanup',
    },
  });
  const batchCancelPayload = parseJsonContent<{
    cancelled_count: number;
    cancelled: Array<{ id: string; status: string; list_id: string | null; body: string | null; ai_notes: string | null }>;
    already_done: string[];
    dependency_updates: Array<{ id: string }>;
    next_occurrences: Array<{
      id: string;
      status: string;
      title: string;
      recurrence: string | null;
      list_id: string | null;
      body: string | null;
      reminders: Array<{ id: string; reminder_at: string }>;
    }>;
  }>(batchCancelResult);

  assert.equal(batchCancelPayload.cancelled_count, 2);
  assert.deepEqual(
    batchCancelPayload.cancelled.map((task) => task.id).sort(),
    [blockerTask.id, recurringTask.id].sort(),
    'batch_cancel_tasks should return the full set of newly cancelled tasks',
  );
  assert.ok(
    batchCancelPayload.cancelled.every((task) => task.status === 'cancelled'),
    'batch_cancel_tasks should return enriched cancelled tasks, not skeletal rows',
  );
  const cancelledRecurringTask = batchCancelPayload.cancelled.find((task) => task.id === recurringTask.id);
  assert.ok(cancelledRecurringTask, 'Recurring task should be present in cancelled batch payload');
  assert.equal(cancelledRecurringTask.list_id, list.id);
  assert.equal(cancelledRecurringTask.body, recurringTask.body);
  assert.ok(
    cancelledRecurringTask.ai_notes?.includes('Cancelled: Batch cleanup'),
    `Cancelled batch payload should surface updated ai_notes, got: ${cancelledRecurringTask.ai_notes}`,
  );
  assert.deepEqual(batchCancelPayload.already_done, []);
  assert.deepEqual(
    batchCancelPayload.dependency_updates.map((task) => task.id),
    [blockedTask.id],
    'Dependent tasks outside the cancel set should be returned in dependency_updates',
  );
  assert.equal(batchCancelPayload.next_occurrences.length, 1);
  const batchCancelSuccessor = requireArrayItem(batchCancelPayload.next_occurrences, 0, 'expected batch cancel successor');
  assert.equal(batchCancelSuccessor.status, 'open');
  assert.equal(batchCancelSuccessor.title, 'Recurring batch cancel task');
  assert.equal(batchCancelSuccessor.recurrence, '{"FREQ":"WEEKLY","INTERVAL":1}');
  assert.equal(batchCancelSuccessor.list_id, list.id);
  assert.equal(batchCancelSuccessor.body, recurringTask.body);
  assert.equal(
    batchCancelSuccessor.reminders.length,
    1,
    'skip-cancel successor should carry forward the parent reminder',
  );
  assert.equal(
    requireArrayItem(batchCancelSuccessor.reminders, 0, 'expected successor reminder').reminder_at,
    '2099-05-17T09:00:00.000Z',
  );

  const db = new Database(harness.dbPath, { readonly: true });
  t.after(() => { db.close(); });

  const blockerNotes = db.prepare(
    'SELECT status, ai_notes FROM tasks WHERE id = ?',
  ).get(blockerTask.id) as { status: string; ai_notes: string | null } | undefined;
  assert.ok(blockerNotes, 'Cancelled blocker task should remain queryable');
  assert.equal(blockerNotes.status, 'cancelled');
  assert.ok(
    blockerNotes.ai_notes?.includes('Cancelled: Batch cleanup'),
    `batch_cancel_tasks reason should be appended to ai_notes, got: ${blockerNotes.ai_notes}`,
  );

  const recurringRow = db.prepare(
    'SELECT status, ai_notes FROM tasks WHERE id = ?',
  ).get(recurringTask.id) as { status: string; ai_notes: string | null } | undefined;
  assert.ok(recurringRow, 'Recurring cancelled task should remain queryable');
  assert.equal(recurringRow.status, 'cancelled');
  assert.ok(
    recurringRow.ai_notes?.includes('Cancelled: Batch cleanup'),
    `Recurring task ai_notes should contain batch cancel reason, got: ${recurringRow.ai_notes}`,
  );

  const dependencyRows = db.prepare(
    'SELECT depends_on_task_id FROM task_dependencies WHERE task_id = ?',
  ).all(blockedTask.id) as Array<{ depends_on_task_id: string }>;
  assert.ok(
    !dependencyRows.some((row) => row.depends_on_task_id === blockerTask.id),
    'batch_cancel_tasks should remove dependency edges pointing at cancelled tasks',
  );

  const successorRow = db.prepare(
    'SELECT status, recurrence FROM tasks WHERE id = ?',
  ).get(batchCancelSuccessor.id) as { status: string; recurrence: string | null } | undefined;
  assert.ok(successorRow, 'Recurring cancel should spawn a successor row');
  assert.equal(successorRow.status, 'open');
  assert.equal(successorRow.recurrence, '{"FREQ":"WEEKLY","INTERVAL":1}');

});

test('batch_cancel_tasks with cancel_series=true stops recurring series without spawning successor', async (t) => {
  const harness = await createHarness('batch-cancel-stop-series');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const recurringTaskResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Recurring task to stop entirely',
      due_date: '2026-05-20',
      recurrence: { freq: 'weekly', interval: 1 },
      reminders: ['2026-05-19T08:00:00Z'],
    },
  });
  const recurringTask = parseTaskEnvelope<{ id: string }>(recurringTaskResult);

  const cancelResult = await client.callTool({
    name: 'batch_cancel_tasks',
    arguments: {
      task_ids: [recurringTask.id],
      cancel_series: true,
      reason: 'Stop the entire series',
    },
  });
  const cancelPayload = parseJsonContent<{
    cancelled_count: number;
    cancelled: Array<{ id: string; status: string; recurrence: string | null; ai_notes: string | null }>;
    next_occurrences: Array<{ id: string }>;
  }>(cancelResult);

  assert.equal(cancelPayload.cancelled_count, 1);
  assert.equal(cancelPayload.cancelled.length, 1);
  const cancelledSeriesTask = requireArrayItem(cancelPayload.cancelled, 0, 'expected cancelled recurring task');
  assert.equal(cancelledSeriesTask.id, recurringTask.id);
  assert.equal(cancelledSeriesTask.status, 'cancelled');
  assert.equal(
    cancelledSeriesTask.recurrence,
    null,
    'cancel_series=true should clear recurrence fields on the cancelled task',
  );
  assert.ok(
    cancelledSeriesTask.ai_notes?.includes('Cancelled: Stop the entire series'),
    `cancel_series=true should still append the batch reason, got: ${cancelledSeriesTask.ai_notes}`,
  );
  assert.deepEqual(
    cancelPayload.next_occurrences,
    [],
    'cancel_series=true should stop the series instead of spawning a successor',
  );

  const db = new Database(harness.dbPath, { readonly: true });
  t.after(() => { db.close(); });

  const cancelledRow = db.prepare(
    'SELECT status, recurrence, recurrence_group_id, canonical_occurrence_date FROM tasks WHERE id = ?',
  ).get(recurringTask.id) as {
    status: string;
    recurrence: string | null;
    recurrence_group_id: string | null;
    canonical_occurrence_date: string | null;
  } | undefined;
  assert.ok(cancelledRow, 'Cancelled recurring task should remain queryable');
  assert.equal(cancelledRow.status, 'cancelled');
  assert.equal(cancelledRow.recurrence, null);
  assert.equal(cancelledRow.recurrence_group_id, null);
  assert.equal(cancelledRow.canonical_occurrence_date, null);
  const exceptionCount = db.prepare(
    'SELECT COUNT(*) AS count FROM task_recurrence_exceptions WHERE task_id = ?',
  ).get(recurringTask.id) as { count: number };
  assert.equal(exceptionCount.count, 0);

  const successorRows = db.prepare(
    'SELECT id FROM tasks WHERE spawned_from = ? ORDER BY created_at ASC',
  ).all(recurringTask.id) as Array<{ id: string }>;
  assert.deepEqual(
    successorRows,
    [],
    'cancel_series=true should leave no spawned successor rows behind',
  );
});

test('batch_cancel_tasks rejects all-terminal batches instead of returning no-op success', async (t) => {
  const harness = await createHarness('batch-cancel-noop');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const completedTaskResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Already completed task' },
  });
  const completedTask = parseTaskEnvelope<{ id: string }>(completedTaskResult);
  await client.callTool({
    name: 'complete_task',
    arguments: { id: completedTask.id },
  });

  const cancelledTaskResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Already cancelled task' },
  });
  const cancelledTask = parseTaskEnvelope<{ id: string }>(cancelledTaskResult);
  await client.callTool({
    name: 'cancel_task',
    arguments: { id: cancelledTask.id, reason: 'Already stopped' },
  });

  const noopResult = asToolResultPayload(await client.callTool({
    name: 'batch_cancel_tasks',
    arguments: { task_ids: [completedTask.id, cancelledTask.id] },
  }));
  const noopPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(noopResult);

  assert.equal(noopResult.isError, true);
  assert.equal(noopPayload.kind, 'validation');
  assert.match(noopPayload.message, /batch_cancel_tasks rejects partial application/);
  assert.match(noopPayload.message, new RegExp(completedTask.id));
  assert.match(noopPayload.message, new RegExp(cancelledTask.id));
  assert.equal(noopPayload.retryable, false);
});

test('reopen_task reopens cancelled tasks and restores their cancelled reminders', async (t) => {
  const harness = await createHarness('reopen-cancelled-task-direct');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const taskResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Cancelled reopen target',
      reminders: ['2026-05-19T08:00:00Z'],
    },
  });
  const task = parseTaskEnvelope<{ id: string }>(taskResult);

  await client.callTool({
    name: 'cancel_task',
    arguments: { id: task.id, reason: 'Pause for now' },
  });

  const db = new Database(harness.dbPath);
  t.after(() => { db.close(); });

  const reminderBeforeReopen = db.prepare(
    'SELECT id, cancelled_at FROM task_reminders WHERE task_id = ? ORDER BY id LIMIT 1',
  ).get(task.id) as { id: string; cancelled_at: string | null } | undefined;
  assert.ok(reminderBeforeReopen, 'Expected cancelled task reminder to remain queryable');
  assert.ok(
    reminderBeforeReopen.cancelled_at,
    'Cancelling the task should mark its reminder as cancelled before reopen',
  );

  const reopenedTask = parseJsonContent<{ id: string; status: string }>(await client.callTool({
    name: 'reopen_task',
    arguments: { id: task.id },
  }));
  assert.equal(reopenedTask.id, task.id);
  assert.equal(reopenedTask.status, 'open');

  const reminderAfterReopen = db.prepare(
    'SELECT cancelled_at FROM task_reminders WHERE id = ?',
  ).get(reminderBeforeReopen.id) as { cancelled_at: string | null } | undefined;
  assert.ok(reminderAfterReopen, 'Expected cancelled reminder row to remain present after reopen');
  assert.equal(
    reminderAfterReopen.cancelled_at,
    null,
    'reopen_task should clear cancelled_at when reopening a cancelled task',
  );
});

test('reopen_task rejects open tasks, clears stale defer metadata, and reopens completed recurring tasks while uncancelling original reminders', async (t) => {
  const harness = await createHarness('reopen-task-direct');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const openTaskResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Already open task' },
  });
  const openTask = parseTaskEnvelope<{ id: string }>(openTaskResult);

  const alreadyOpenResult = asToolResultPayload(await client.callTool({
    name: 'reopen_task',
    arguments: { id: openTask.id },
  }));
  assert.equal(alreadyOpenResult.isError, true, 'reopen_task should reject already-open tasks');
  const alreadyOpenPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(alreadyOpenResult);
  assert.equal(alreadyOpenPayload.kind, 'validation');
  assert.match(alreadyOpenPayload.message, /already open/);
  assert.equal(alreadyOpenPayload.retryable, false);

  const recurringTaskResult = await client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Recurring reopen target',
      due_date: '2099-05-20',
      recurrence: { freq: 'weekly', interval: 1 },
      reminders: ['2099-05-19T08:00:00Z'],
    },
  });
  const recurringTask = parseTaskEnvelope<{ id: string }>(recurringTaskResult);

  const completed = parseJsonContent<{
    completed: { id: string; status: string };
    next_occurrence: { id: string; status: string } | null;
  }>(await client.callTool({
    name: 'complete_task',
    arguments: { id: recurringTask.id },
  }));
  assert.equal(completed.completed.status, 'completed');
  assert.ok(completed.next_occurrence, 'Completing a recurring task should spawn a successor');

  const db = new Database(harness.dbPath);
  t.after(() => { db.close(); });

  const reminderBeforeReopen = db.prepare(
    'SELECT id, cancelled_at FROM task_reminders WHERE task_id = ? ORDER BY id LIMIT 1',
  ).get(recurringTask.id) as { id: string; cancelled_at: string | null } | undefined;
  assert.ok(reminderBeforeReopen, 'Expected the recurring task reminder to remain queryable');
  assert.ok(
    reminderBeforeReopen.cancelled_at,
    'Completing the task should cancel the original reminder before reopen',
  );

  const successorReminderBeforeReopen = db.prepare(
    'SELECT id, reminder_at, cancelled_at FROM task_reminders WHERE task_id = ? ORDER BY id LIMIT 1',
  ).get(completed.next_occurrence!.id) as {
    id: string;
    reminder_at: string;
    cancelled_at: string | null;
  } | undefined;
  assert.ok(
    successorReminderBeforeReopen,
    'Completing a recurring task should copy an active reminder onto the spawned successor',
  );
  assert.equal(successorReminderBeforeReopen.cancelled_at, null);
  assert.equal(successorReminderBeforeReopen.reminder_at, '2099-05-26T08:00:00.000Z');

  db.prepare(
    'UPDATE tasks SET planned_date = ?, defer_count = ?, last_deferred_at = ? WHERE id = ?',
  ).run('2099-05-18', 3, '2099-05-18T09:30:00Z', recurringTask.id);

  const reopenedTask = parseJsonContent<{
    id: string;
    status: string;
    recurrence: string | null;
    completed_at: string | null;
    planned_date: string | null;
    defer_count: number;
    last_deferred_at: string | null;
  }>(await client.callTool({
    name: 'reopen_task',
    arguments: { id: recurringTask.id },
  }));
  assert.equal(reopenedTask.id, recurringTask.id);
  assert.equal(reopenedTask.status, 'open');
  assert.equal(reopenedTask.recurrence, '{"FREQ":"WEEKLY","INTERVAL":1}');
  assert.equal(reopenedTask.completed_at, null, 'reopen_task should clear completed_at on the reopened task');
  assert.equal(reopenedTask.planned_date, null, 'reopen_task should clear planned_date on the reopened task');
  assert.equal(reopenedTask.defer_count, 0, 'reopen_task should zero defer_count on the reopened task');
  assert.equal(
    reopenedTask.last_deferred_at,
    null,
    'reopen_task should clear last_deferred_at on the reopened task',
  );

  const successorAfterReopen = db.prepare(
    'SELECT status FROM tasks WHERE id = ?',
  ).get(completed.next_occurrence!.id) as { status: string } | undefined;
  assert.ok(successorAfterReopen, 'Expected spawned successor to remain queryable after reopen');
  assert.equal(
    successorAfterReopen.status,
    'cancelled',
    'Reopening a completed recurring task should cancel its spawned successor',
  );

  const reminderAfterReopen = db.prepare(
    'SELECT cancelled_at FROM task_reminders WHERE id = ?',
  ).get(reminderBeforeReopen.id) as { cancelled_at: string | null } | undefined;
  assert.ok(reminderAfterReopen, 'Expected original reminder row to remain present after reopen');
  assert.equal(
    reminderAfterReopen.cancelled_at,
    null,
    'reopen_task should un-cancel reminders from the reopened task',
  );

  const reopenedRow = db.prepare(
    'SELECT planned_date, defer_count, last_deferred_at FROM tasks WHERE id = ?',
  ).get(recurringTask.id) as {
    planned_date: string | null;
    defer_count: number;
    last_deferred_at: string | null;
  } | undefined;
  assert.ok(reopenedRow, 'Expected reopened task row to remain queryable');
  assert.equal(reopenedRow.planned_date, null);
  assert.equal(reopenedRow.defer_count, 0);
  assert.equal(reopenedRow.last_deferred_at, null);
});

test('update_task clears nullable fields and cleans deps on cancel', async (t) => {
  const harness = await createHarness('update-task-nullable-cancel');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const taskAResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Task A', planned_date: '2026-04-01' },
  });
  const taskA = parseTaskEnvelope<{ id: string; planned_date: string | null }>(taskAResult);
  assert.equal(taskA.planned_date, '2026-04-01', 'planned_date should be set on create');

  const taskBResult = await client.callTool({
    name: 'create_task',
    arguments: { title: 'Task B', depends_on: [taskA.id] },
  });
  const taskB = parseTaskEnvelope<{ id: string }>(taskBResult);

  const db = new Database(harness.dbPath, { readonly: true });
  t.after(() => { db.close(); });

  // Verify Task B depends on Task A (via edge table)
  const bDeps1 = db.prepare(
    'SELECT depends_on_task_id FROM task_dependencies WHERE task_id = ?'
  ).all(taskB.id) as { depends_on_task_id: string }[];
  assert.ok(bDeps1.length > 0, 'Task B should have dependencies after creation');
  assert.ok(bDeps1.some(r => r.depends_on_task_id === taskA.id), 'Task B should depend on Task A');

  const clearResult = await client.callTool({
    name: 'update_task',
    arguments: { id: taskA.id, planned_date: null },
  });
  const cleared = parseJsonContent<{ id: string; planned_date: string | null }>(clearResult);
  assert.equal(cleared.planned_date, null, 'planned_date should be null after clearing');

  const cancelResult = await client.callTool({
    name: 'update_task',
    arguments: { id: taskA.id, status: 'cancelled' },
  });
  const cancelled = parseJsonContent<{ id: string; status: string }>(cancelResult);
  assert.equal(cancelled.status, 'cancelled', 'Task A should be cancelled');

  const bDeps = db.prepare(
    'SELECT depends_on_task_id FROM task_dependencies WHERE task_id = ?'
  ).all(taskB.id) as { depends_on_task_id: string }[];
  const bDepIds = bDeps.map(r => r.depends_on_task_id);
  assert.ok(!bDepIds.includes(taskA.id), `Task B should not depend on cancelled Task A, got: ${JSON.stringify(bDepIds)}`);
});
