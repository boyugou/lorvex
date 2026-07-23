import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  asToolResultPayload,
  createHarness,
  daysFromTodayYmd,
  parseJsonContent,
  requireArrayItem,
  requireValue,
} from '../shared';

test('advanced task lifecycle mutations preserve rich direct MCP contracts', async (t) => {
  const harness = await createHarness('task-advanced-lifecycle');
  t.after(async () => {
    await harness.cleanup();
  });

  const { client } = harness;
  const today = daysFromTodayYmd();
  const nextWeek = daysFromTodayYmd(7);

  const sourceList = parseJsonContent<{ id: string }>(await client.callTool({
    name: 'create_list',
    arguments: { name: 'Advanced Source List' },
  }));
  const destinationList = parseJsonContent<{ id: string }>(await client.callTool({
    name: 'create_list',
    arguments: { name: 'Advanced Destination List' },
  }));

  const createTask = async (title: string, args: Record<string, unknown> = {}) => {
    const result = asToolResultPayload(await client.callTool({
      name: 'create_task',
      arguments: {
        title,
        list_id: sourceList.id,
        ...args,
      },
    }));
    const payload = parseJsonContent<{
      task: {
        id: string;
        title: string;
        status: string;
        list_id: string | null;
        body: string | null;
        recurrence: string | null;
        recurrence_exceptions: string | null;
        reminders: Array<{ id: string; reminder_at: string }>;
      };
    }>(result);
    assert.ok(payload.task, 'create_task must return an envelope with a task field');
    return payload.task;
  };

  const recurringTask = await createTask('Recurring lifecycle task', {
    due_date: today,
    recurrence: { freq: 'weekly', interval: 1 },
    body: 'Initial task body.',
    reminders: ['2026-05-01T09:00:00Z', '2026-05-02T10:00:00Z'],
  });
  const reopenTarget = await createTask('Task to batch reopen');
  const moveTarget = await createTask('Task to batch move');
  await client.callTool({
    name: 'complete_task',
    arguments: { id: reopenTarget.id },
  });

  const appendedTask = parseJsonContent<{
    id: string;
    body: string | null;
  }>(await client.callTool({
    name: 'append_to_task_body',
    arguments: {
      id: recurringTask.id,
      text: 'Follow-up note for the weekly recurrence.',
    },
  }));
  assert.equal(appendedTask.id, recurringTask.id);
  assert.equal(
    appendedTask.body,
    'Initial task body.\n\nFollow-up note for the weekly recurrence.',
    'append_to_task_body should preserve the existing body and insert a blank-line separator',
  );

  const reminderToRemove = recurringTask.reminders.find((reminder) => reminder.reminder_at.includes('2026-05-01'));
  const reminderToRemoveId = requireValue(reminderToRemove, 'Expected an initial reminder to remove').id;
  const afterReminderRemoval = parseJsonContent<{
    id: string;
    reminders: Array<{ id: string; reminder_at: string }>;
  }>(await client.callTool({
    name: 'remove_task_reminder',
    arguments: {
      task_id: recurringTask.id,
      reminder_id: reminderToRemoveId,
    },
  }));
  assert.equal(afterReminderRemoval.id, recurringTask.id);
  assert.equal(afterReminderRemoval.reminders.length, 1);
  assert.notEqual(
    requireArrayItem(afterReminderRemoval.reminders, 0, 'expected remaining reminder').id,
    reminderToRemoveId,
  );

  const withException = parseJsonContent<{
    id: string;
    recurrence_exceptions: string | null;
  }>(await client.callTool({
    name: 'add_task_recurrence_exception',
    arguments: {
      task_id: recurringTask.id,
      exception_date: nextWeek,
    },
  }));
  assert.equal(withException.id, recurringTask.id);
  assert.equal(withException.recurrence_exceptions, `["${nextWeek}"]`);

  const withoutException = parseJsonContent<{
    id: string;
    recurrence_exceptions: string | null;
  }>(await client.callTool({
    name: 'remove_task_recurrence_exception',
    arguments: {
      task_id: recurringTask.id,
      exception_date: nextWeek,
    },
  }));
  assert.equal(withoutException.id, recurringTask.id);
  assert.equal(withoutException.recurrence_exceptions, '[]');

  const movedTasks = parseJsonContent<{
    moved_count: number;
    list_id: string;
    tasks: Array<{
      id: string;
      title: string;
      list_id: string | null;
      body: string | null;
      recurrence: string | null;
      reminders: Array<{ id: string; reminder_at: string }>;
    }>;
  }>(await client.callTool({
    name: 'batch_move_tasks',
    arguments: {
      task_ids: [recurringTask.id, moveTarget.id],
      list_id: destinationList.id,
    },
  }));
  assert.equal(movedTasks.moved_count, 2);
  assert.equal(movedTasks.list_id, destinationList.id);
  assert.deepEqual(
    movedTasks.tasks.map((task) => task.id).sort(),
    [recurringTask.id, moveTarget.id].sort(),
  );
  assert.deepEqual(
    movedTasks.tasks.map((task) => task.list_id),
    [destinationList.id, destinationList.id],
  );
  const movedRecurringTask = movedTasks.tasks.find((task) => task.id === recurringTask.id);
  assert.ok(movedRecurringTask, 'Expected recurring task to be present in batch_move_tasks response');
  assert.equal(movedRecurringTask.title, 'Recurring lifecycle task');
  assert.equal(movedRecurringTask.list_id, destinationList.id);
  assert.equal(
    movedRecurringTask.body,
    'Initial task body.\n\nFollow-up note for the weekly recurrence.',
    'batch_move_tasks should return enriched task payloads including the latest body content',
  );
  assert.equal(movedRecurringTask.recurrence, '{"FREQ":"WEEKLY","INTERVAL":1}');
  assert.equal(movedRecurringTask.reminders.length, 1);

  const completedBatch = parseJsonContent<{
    completed_count: number;
    tasks: Array<{
      id: string;
      title: string;
      status: string;
      list_id: string | null;
      body: string | null;
      recurrence: string | null;
    }>;
    next_occurrences: Array<{
      id: string;
      title: string;
      status: string;
      list_id: string | null;
      body: string | null;
      recurrence: string | null;
    }>;
  }>(await client.callTool({
    name: 'batch_complete_tasks',
    arguments: {
      task_ids: [recurringTask.id, moveTarget.id],
    },
  }));
  assert.equal(completedBatch.completed_count, 2);
  assert.deepEqual(
    completedBatch.tasks.map((task) => `${task.id}:${task.status}`).sort(),
    [`${recurringTask.id}:completed`, `${moveTarget.id}:completed`].sort(),
  );
  assert.equal(completedBatch.next_occurrences.length, 1);
  const recurringCompletedTask = completedBatch.tasks.find((task) => task.id === recurringTask.id);
  assert.ok(recurringCompletedTask, 'Expected recurring task to be present in batch_complete_tasks response');
  assert.equal(recurringCompletedTask.title, 'Recurring lifecycle task');
  assert.equal(recurringCompletedTask.list_id, destinationList.id);
  assert.equal(
    recurringCompletedTask.body,
    'Initial task body.\n\nFollow-up note for the weekly recurrence.',
    'batch_complete_tasks should return full updated task objects, not skeletal rows',
  );
  assert.equal(recurringCompletedTask.recurrence, '{"FREQ":"WEEKLY","INTERVAL":1}');
  const spawnedSuccessor = requireArrayItem(
    completedBatch.next_occurrences,
    0,
    'expected spawned recurring successor',
  );
  assert.equal(spawnedSuccessor.status, 'open');
  assert.equal(spawnedSuccessor.title, 'Recurring lifecycle task');
  assert.equal(spawnedSuccessor.list_id, destinationList.id);
  assert.equal(spawnedSuccessor.body, 'Initial task body.\n\nFollow-up note for the weekly recurrence.');
  assert.equal(
    spawnedSuccessor.recurrence,
    '{"FREQ":"WEEKLY","INTERVAL":1}',
    'Recurring completion should preserve the exact normalized recurrence payload on the successor',
  );

  const reopenedBatch = parseJsonContent<{
    reopened_count: number;
    reopened: Array<{
      id: string;
      title: string;
      status: string;
      list_id: string | null;
      body: string | null;
      recurrence: string | null;
    }>;
    already_open: string[];
  }>(await client.callTool({
    name: 'batch_reopen_tasks',
    arguments: {
      task_ids: [reopenTarget.id, recurringCompletedTask!.id],
    },
  }));
  assert.equal(reopenedBatch.reopened_count, 2);
  assert.deepEqual(reopenedBatch.already_open, []);
  assert.deepEqual(
    reopenedBatch.reopened.map((task) => task.id).sort(),
    [reopenTarget.id, recurringCompletedTask!.id].sort(),
  );
  assert.deepEqual(
    reopenedBatch.reopened.map((task) => task.status),
    ['open', 'open'],
  );
  const reopenedRecurringTask = reopenedBatch.reopened.find((task) => task.id === recurringCompletedTask!.id);
  assert.ok(reopenedRecurringTask, 'Expected recurring task to be present in batch_reopen_tasks response');
  assert.equal(reopenedRecurringTask.title, 'Recurring lifecycle task');
  assert.equal(reopenedRecurringTask.list_id, destinationList.id);
  assert.equal(reopenedRecurringTask.body, 'Initial task body.\n\nFollow-up note for the weekly recurrence.');
  assert.equal(reopenedRecurringTask.recurrence, '{"FREQ":"WEEKLY","INTERVAL":1}');

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const movedRows = db.prepare(
    'SELECT id, list_id, status FROM tasks WHERE id IN (?, ?) ORDER BY id',
  ).all(recurringTask.id, moveTarget.id) as Array<{ id: string; list_id: string | null; status: string }>;
  assert.equal(movedRows.length, 2);
  assert.ok(movedRows.every((row) => row.list_id === destinationList.id), 'Moved tasks should persist destination list_id');

  const reopenedRows = db.prepare(
    'SELECT id, status FROM tasks WHERE id IN (?, ?) ORDER BY id',
  ).all(reopenTarget.id, recurringCompletedTask!.id) as Array<{ id: string; status: string }>;
  assert.equal(reopenedRows.length, 2, 'Expected both reopened tasks to remain queryable after batch_reopen_tasks');
  assert.ok(reopenedRows.every((row) => row.status === 'open'), 'Reopened tasks should persist open status');

  const successorAfterReopen = db.prepare(
    'SELECT status FROM tasks WHERE id = ?',
  ).get(spawnedSuccessor.id) as { status: string } | undefined;
  assert.ok(successorAfterReopen, 'Expected spawned successor row to remain queryable after reopen');
  assert.equal(
    successorAfterReopen.status,
    'cancelled',
    'Reopening a completed recurring parent should cancel its auto-spawned successor',
  );

  const remainingReminderRows = db.prepare(
    'SELECT COUNT(*) AS count FROM task_reminders WHERE task_id = ?',
  ).get(recurringTask.id) as { count: number };
  assert.equal(remainingReminderRows.count, 1, 'Expected remove_task_reminder to delete exactly one reminder row');
  const removedReminderSyncRows = db.prepare(
    'SELECT COUNT(*) AS count FROM sync_outbox WHERE entity_type = ? AND entity_id = ? AND operation = ?',
  ).get('task_reminder', reminderToRemove!.id, 'delete') as { count: number };
  assert.equal(
    removedReminderSyncRows.count,
    1,
    'remove_task_reminder should enqueue exactly one task_reminder delete envelope for sync',
  );

  const recurrenceExceptionCount = db.prepare(
    'SELECT COUNT(*) AS count FROM task_recurrence_exceptions WHERE task_id = ?',
  ).get(recurringTask.id) as { count: number };
  assert.equal(recurrenceExceptionCount.count, 0, 'Expected removed exception to clear persisted recurrence exceptions');

  const aiChangelogTools = db.prepare(`
    SELECT DISTINCT mcp_tool
    FROM ai_changelog
    WHERE mcp_tool IN (
      'append_to_task_body',
      'remove_task_reminder',
      'add_task_recurrence_exception',
      'remove_task_recurrence_exception',
      'batch_move_tasks',
      'batch_complete_tasks',
      'batch_reopen_tasks'
    )
  `).all() as Array<{ mcp_tool: string }>;
  assert.deepEqual(
    aiChangelogTools.map((row) => row.mcp_tool).sort(),
    [
      'add_task_recurrence_exception',
      'append_to_task_body',
      'batch_complete_tasks',
      'batch_move_tasks',
      'batch_reopen_tasks',
      'remove_task_recurrence_exception',
      'remove_task_reminder',
    ],
  );
});
