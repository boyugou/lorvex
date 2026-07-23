import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  asToolResultPayload,
  createHarness,
  parseJsonContent,
  insertListSeed,
  insertTaskSeed,
  requireArrayItem,
} from './shared';

const SEED_VERSION = '0000000000000_0000_00000000';

function resetAuditTables(db: Database.Database): void {
  db.exec(`
    DELETE FROM ai_changelog;
    DELETE FROM sync_outbox;
  `);
}

test('update_list and reorganize_list preserve rich direct MCP contracts', async (t) => {
  const harness = await createHarness('list-mutations-update-reorganize');
  t.after(async () => {
    await harness.cleanup();
  });

  const db = new Database(harness.dbPath);
  t.after(() => db.close());

  insertListSeed(db, {
    id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
    name: 'Contract List',
    color: '#123456',
    icon: 'tray',
  });
  insertTaskSeed(db, {
    id: '01966a3f-7c8b-7d4e-8f3a-000000000603',
    title: 'Priority two task',
    list_id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
    priority: 2,
    due_date: '2026-05-12',
  });
  insertTaskSeed(db, {
    id: '01966a3f-7c8b-7d4e-8f3a-000000000602',
    title: 'Priority one task',
    list_id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
    priority: 1,
    due_date: '2026-05-15',
  });
  insertTaskSeed(db, {
    id: '01966a3f-7c8b-7d4e-8f3a-000000000601',
    title: 'Priority one earlier due date',
    list_id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
    priority: 1,
    due_date: '2026-05-10',
  });
  insertTaskSeed(db, {
    id: '01966a3f-7c8b-7d4e-8f3a-000000000604',
    title: 'Completed task should be filtered',
    list_id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
    priority: 1,
    due_date: '2026-05-09',
    status: 'completed',
  });
  insertListSeed(db, {
    id: '01966a3f-7c8b-7d4e-8f3a-000000000502',
    name: 'Other List',
  });
  insertListSeed(db, {
    id: '01966a3f-7c8b-7d4e-8f3a-000000000503',
    name: 'Empty List',
  });
  insertTaskSeed(db, {
    id: '01966a3f-7c8b-7d4e-8f3a-000000000605',
    title: 'Task in another list',
    list_id: '01966a3f-7c8b-7d4e-8f3a-000000000502',
    priority: 3,
  });
  resetAuditTables(db);

  const updatedList = parseJsonContent<{
    id: string;
    name: string;
    color: string | null;
    icon: string | null;
    description: string | null;
    ai_notes: string | null;
  }>(await harness.client.callTool({
    name: 'update_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      name: 'Contract List Renamed',
      color: '#654321',
      icon: 'sparkles',
      description: 'List description for direct MCP coverage.',
      ai_notes: 'AI-only list note.',
    },
  }));
  assert.equal(updatedList.id, '01966a3f-7c8b-7d4e-8f3a-000000000501');
  assert.equal(updatedList.name, 'Contract List Renamed');
  assert.equal(updatedList.color, '#654321');
  assert.equal(updatedList.icon, 'sparkles');
  assert.equal(updatedList.description, 'List description for direct MCP coverage.');
  assert.equal(updatedList.ai_notes, 'AI-only list note.');

  const clearedList = parseJsonContent<{
    id: string;
    name: string;
    color: string | null;
    icon: string | null;
    description: string | null;
    ai_notes: string | null;
  }>(await harness.client.callTool({
    name: 'update_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      color: null,
      icon: null,
      description: null,
      ai_notes: null,
    },
  }));
  assert.equal(clearedList.id, '01966a3f-7c8b-7d4e-8f3a-000000000501');
  assert.equal(clearedList.name, 'Contract List Renamed');
  assert.equal(clearedList.color, null);
  assert.equal(clearedList.icon, null);
  assert.equal(clearedList.description, null);
  assert.equal(clearedList.ai_notes, null);

  const aiChangelogRowsAfterUpdates = db.prepare(
    'SELECT COUNT(*) AS count FROM ai_changelog WHERE mcp_tool = ?',
  ).get('update_list') as { count: number };
  assert.equal(aiChangelogRowsAfterUpdates.count, 2, 'Each mutating update_list call should append an ai_changelog row');
  const updateChangelogRows = db.prepare(
    'SELECT before_json, after_json FROM ai_changelog WHERE mcp_tool = ? ORDER BY id',
  ).all('update_list') as Array<{ before_json: string | null; after_json: string | null }>;
  assert.equal(updateChangelogRows.length, 2);
  const firstChangelogRow = requireArrayItem(updateChangelogRows, 0, 'expected first update_list changelog row');
  const secondChangelogRow = requireArrayItem(updateChangelogRows, 1, 'expected second update_list changelog row');
  const firstBefore = JSON.parse(firstChangelogRow.before_json ?? 'null') as {
    name: string;
    color: string | null;
    icon: string | null;
    description: string | null;
    ai_notes: string | null;
  };
  const firstAfter = JSON.parse(firstChangelogRow.after_json ?? 'null') as {
    name: string;
    color: string | null;
    icon: string | null;
    description: string | null;
    ai_notes: string | null;
  };
  assert.equal(firstBefore.name, 'Contract List');
  assert.equal(firstBefore.color, '#123456');
  assert.equal(firstBefore.icon, 'tray');
  assert.equal(firstBefore.description, null);
  assert.equal(firstBefore.ai_notes, null);
  assert.equal(firstAfter.name, 'Contract List Renamed');
  assert.equal(firstAfter.color, '#654321');
  assert.equal(firstAfter.icon, 'sparkles');
  assert.equal(firstAfter.description, 'List description for direct MCP coverage.');
  assert.equal(firstAfter.ai_notes, 'AI-only list note.');
  const secondBefore = JSON.parse(secondChangelogRow.before_json ?? 'null') as {
    color: string | null;
    icon: string | null;
    description: string | null;
    ai_notes: string | null;
  };
  const secondAfter = JSON.parse(secondChangelogRow.after_json ?? 'null') as {
    color: string | null;
    icon: string | null;
    description: string | null;
    ai_notes: string | null;
  };
  assert.equal(secondBefore.color, '#654321');
  assert.equal(secondBefore.icon, 'sparkles');
  assert.equal(secondBefore.description, 'List description for direct MCP coverage.');
  assert.equal(secondBefore.ai_notes, 'AI-only list note.');
  assert.equal(secondAfter.color, null);
  assert.equal(secondAfter.icon, null);
  assert.equal(secondAfter.description, null);
  assert.equal(secondAfter.ai_notes, null);
  const listSyncRowsAfterUpdates = db.prepare(
    'SELECT COUNT(*) AS count FROM sync_outbox WHERE entity_type = ? AND entity_id = ? AND operation = ?',
  ).get('list', '01966a3f-7c8b-7d4e-8f3a-000000000501', 'upsert') as { count: number };
  assert.equal(
    listSyncRowsAfterUpdates.count,
    1,
    'Repeated update_list calls on the same entity should coalesce to the latest list upsert in sync_outbox',
  );
  const coalescedListPayloadRow = db.prepare(
    'SELECT payload FROM sync_outbox WHERE entity_type = ? AND entity_id = ? AND operation = ?',
  ).get('list', '01966a3f-7c8b-7d4e-8f3a-000000000501', 'upsert') as { payload: string } | undefined;
  assert.ok(coalescedListPayloadRow, 'Expected a coalesced list upsert row in sync_outbox');
  const coalescedListPayload = JSON.parse(coalescedListPayloadRow.payload) as {
    name: string;
    color: string | null;
    icon: string | null;
    description: string | null;
    ai_notes: string | null;
  };
  assert.equal(coalescedListPayload.name, 'Contract List Renamed');
  assert.equal(coalescedListPayload.color, null);
  assert.equal(coalescedListPayload.icon, null);
  assert.equal(coalescedListPayload.description, null);
  assert.equal(coalescedListPayload.ai_notes, null);

  const noOpList = parseJsonContent<{
    id: string;
    name: string;
    color: string | null;
    icon: string | null;
    description: string | null;
    ai_notes: string | null;
  }>(await harness.client.callTool({
    name: 'update_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
    },
  }));
  assert.deepEqual(noOpList, clearedList, 'A no-op update_list call should return the unchanged list row');
  const aiChangelogRowsAfterNoOp = db.prepare(
    'SELECT COUNT(*) AS count FROM ai_changelog WHERE mcp_tool = ?',
  ).get('update_list') as { count: number };
  assert.equal(aiChangelogRowsAfterNoOp.count, 2, 'No-op update_list should not append a fresh ai_changelog row');
  const listSyncRowsAfterNoOp = db.prepare(
    'SELECT COUNT(*) AS count FROM sync_outbox WHERE entity_type = ? AND entity_id = ? AND operation = ?',
  ).get('list', '01966a3f-7c8b-7d4e-8f3a-000000000501', 'upsert') as { count: number };
  assert.equal(listSyncRowsAfterNoOp.count, 1, 'No-op update_list should not enqueue an extra list upsert');

  const invalidNameUpdate = asToolResultPayload(await harness.client.callTool({
    name: 'update_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      name: '   ',
    },
  }));
  assert.equal(invalidNameUpdate.isError, true, 'update_list should reject whitespace-only names');
  const invalidNamePayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(invalidNameUpdate);
  assert.equal(invalidNamePayload.kind, 'validation');
  assert.match(invalidNamePayload.message, /list name must not be empty/);
  assert.equal(invalidNamePayload.retryable, false);

  resetAuditTables(db);

  const reorganized = parseJsonContent<{
    id: string;
    name: string;
    tasks: Array<{ id: string; title: string; priority: number | null; due_date: string | null; status: string }>;
  }>(await harness.client.callTool({
    name: 'reorganize_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      strategy: 'priority',
    },
  }));
  assert.equal(reorganized.id, '01966a3f-7c8b-7d4e-8f3a-000000000501');
  assert.equal(reorganized.name, 'Contract List Renamed');
  assert.deepEqual(
    reorganized.tasks.map((task) => task.id),
    ['01966a3f-7c8b-7d4e-8f3a-000000000601', '01966a3f-7c8b-7d4e-8f3a-000000000602', '01966a3f-7c8b-7d4e-8f3a-000000000603'],
    'priority strategy should order open tasks by priority, then due_date',
  );
  assert.ok(
    reorganized.tasks.every((task) => task.status === 'open'),
    'reorganize_list should only return open tasks for computed ordering',
  );

  const manualReorganized = parseJsonContent<{
    id: string;
    tasks: Array<{ id: string }>;
  }>(await harness.client.callTool({
    name: 'reorganize_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      strategy: 'manual',
      task_ids: ['01966a3f-7c8b-7d4e-8f3a-000000000603', '01966a3f-7c8b-7d4e-8f3a-000000000601', '01966a3f-7c8b-7d4e-8f3a-000000000602'],
    },
  }));
  assert.equal(manualReorganized.id, '01966a3f-7c8b-7d4e-8f3a-000000000501');
  assert.deepEqual(
    manualReorganized.tasks.map((task) => task.id),
    ['01966a3f-7c8b-7d4e-8f3a-000000000603', '01966a3f-7c8b-7d4e-8f3a-000000000601', '01966a3f-7c8b-7d4e-8f3a-000000000602'],
    'manual strategy should preserve the caller-supplied task ordering exactly',
  );

  const invalidManualReorganize = asToolResultPayload(await harness.client.callTool({
    name: 'reorganize_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      strategy: 'manual',
      task_ids: ['01966a3f-7c8b-7d4e-8f3a-000000000602', '01966a3f-7c8b-7d4e-8f3a-000000000605'],
    },
  }));
  assert.equal(invalidManualReorganize.isError, true, 'manual reorganize should reject task ids from other lists');
  const invalidManualPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(invalidManualReorganize);
  assert.equal(invalidManualPayload.kind, 'validation');
  assert.match(invalidManualPayload.message, /task\(s\) 01966a3f-7c8b-7d4e-8f3a-000000000605 do not belong to list 01966a3f-7c8b-7d4e-8f3a-000000000501/);
  assert.equal(invalidManualPayload.retryable, false);

  const completedManualReorganize = asToolResultPayload(await harness.client.callTool({
    name: 'reorganize_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      strategy: 'manual',
      task_ids: ['01966a3f-7c8b-7d4e-8f3a-000000000602', '01966a3f-7c8b-7d4e-8f3a-000000000604'],
    },
  }));
  assert.equal(completedManualReorganize.isError, true, 'manual reorganize should reject non-open task ids from the same list');
  const completedManualPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(completedManualReorganize);
  assert.equal(completedManualPayload.kind, 'validation');
  assert.match(completedManualPayload.message, /task\(s\) 01966a3f-7c8b-7d4e-8f3a-000000000604 are not open and cannot be manually reordered/);
  assert.equal(completedManualPayload.retryable, false);

  const missingManualReorganize = asToolResultPayload(await harness.client.callTool({
    name: 'reorganize_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      strategy: 'manual',
      task_ids: ['01966a3f-7c8b-7d4e-8f3a-000000000602', '01966a3f-7c8b-7d4e-8f3a-000000000606'],
    },
  }));
  assert.equal(missingManualReorganize.isError, true, 'manual reorganize should reject nonexistent task ids');
  const missingManualPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(missingManualReorganize);
  assert.equal(missingManualPayload.kind, 'validation');
  assert.match(missingManualPayload.message, /task\(s\) 01966a3f-7c8b-7d4e-8f3a-000000000606 not found/);
  assert.equal(missingManualPayload.retryable, false);

  const missingTaskIdsManualReorganize = asToolResultPayload(await harness.client.callTool({
    name: 'reorganize_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      strategy: 'manual',
    },
  }));
  assert.equal(
    missingTaskIdsManualReorganize.isError,
    true,
    'manual reorganize should require task_ids to be present',
  );
  const missingTaskIdsManualPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(missingTaskIdsManualReorganize);
  assert.equal(missingTaskIdsManualPayload.kind, 'validation');
  assert.match(missingTaskIdsManualPayload.message, /task_ids required for manual strategy/);
  assert.equal(missingTaskIdsManualPayload.retryable, false);

  const emptyManualReorganize = parseJsonContent<{
    id: string;
    tasks: Array<{ id: string }>;
  }>(await harness.client.callTool({
    name: 'reorganize_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000503',
      strategy: 'manual',
      task_ids: [],
    },
  }));
  assert.equal(emptyManualReorganize.id, '01966a3f-7c8b-7d4e-8f3a-000000000503');
  assert.deepEqual(emptyManualReorganize.tasks, [], 'manual reorganize should allow an empty array when the list has no open tasks');

  const duplicateManualReorganize = asToolResultPayload(await harness.client.callTool({
    name: 'reorganize_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      strategy: 'manual',
      task_ids: ['01966a3f-7c8b-7d4e-8f3a-000000000602', '01966a3f-7c8b-7d4e-8f3a-000000000602', '01966a3f-7c8b-7d4e-8f3a-000000000603'],
    },
  }));
  assert.equal(duplicateManualReorganize.isError, true, 'manual reorganize should reject duplicate task ids');
  const duplicateManualPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(duplicateManualReorganize);
  assert.equal(duplicateManualPayload.kind, 'validation');
  assert.match(duplicateManualPayload.message, /task_ids contains duplicate ids: 01966a3f-7c8b-7d4e-8f3a-000000000602/);
  assert.equal(duplicateManualPayload.retryable, false);

  const incompleteManualReorganize = asToolResultPayload(await harness.client.callTool({
    name: 'reorganize_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000501',
      strategy: 'manual',
      task_ids: ['01966a3f-7c8b-7d4e-8f3a-000000000602', '01966a3f-7c8b-7d4e-8f3a-000000000603'],
    },
  }));
  assert.equal(
    incompleteManualReorganize.isError,
    true,
    'manual reorganize should reject incomplete open-task permutations',
  );
  const incompleteManualPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(incompleteManualReorganize);
  assert.equal(incompleteManualPayload.kind, 'validation');
  assert.match(
    incompleteManualPayload.message,
    /task_ids must include every open task in list 01966a3f-7c8b-7d4e-8f3a-000000000501; missing: 01966a3f-7c8b-7d4e-8f3a-000000000601/,
  );
  assert.equal(incompleteManualPayload.retryable, false);

  const reorganizeAuditRows = db.prepare(
    'SELECT COUNT(*) AS count FROM ai_changelog WHERE mcp_tool = ?',
  ).get('reorganize_list') as { count: number };
  assert.equal(
    reorganizeAuditRows.count,
    3,
    'each successful reorganize_list call, including empty-list manual reorder, should write an ai_changelog audit row',
  );
  const businessEntitySyncRows = db.prepare(
    "SELECT COUNT(*) AS count FROM sync_outbox WHERE entity_type IN ('list', 'task')",
  ).get() as { count: number };
  assert.equal(
    businessEntitySyncRows.count,
    0,
    'reorganize_list is a pure computed ordering and should not emit list/task sync envelopes',
  );
});

test('delete_list enforces active-task guard and returns undo-backed delete contract', async (t) => {
  const harness = await createHarness('list-mutations-delete');
  t.after(async () => {
    await harness.cleanup();
  });

  const db = new Database(harness.dbPath);
  t.after(() => db.close());

  insertListSeed(db, {
    id: 'list-keep',
    name: 'Keep List',
    color: '#00aa00',
  });
  insertListSeed(db, {
    id: '01966a3f-7c8b-7d4e-8f3a-000000000505',
    name: 'Drop List',
    color: '#aa0000',
    icon: 'trash',
  });
  insertTaskSeed(db, {
    id: 'task-block-delete',
    title: 'Open task blocks deletion',
    list_id: '01966a3f-7c8b-7d4e-8f3a-000000000505',
    status: 'open',
  });
  insertTaskSeed(db, {
    id: 'task-block-delete-someday',
    title: 'Someday task blocks deletion',
    list_id: '01966a3f-7c8b-7d4e-8f3a-000000000505',
    status: 'someday',
  });
  insertTaskSeed(db, {
    id: 'task-block-delete-completed',
    title: 'Completed task blocks deletion',
    list_id: '01966a3f-7c8b-7d4e-8f3a-000000000505',
    status: 'completed',
  });
  resetAuditTables(db);

  const blockedDelete = asToolResultPayload(await harness.client.callTool({
    name: 'delete_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000505',
    },
  }));
  assert.equal(blockedDelete.isError, true, 'delete_list should reject deleting a list with any assigned task rows');
  const blockedPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(blockedDelete);
  assert.equal(blockedPayload.kind, 'validation');
  assert.match(blockedPayload.message, /Cannot delete list "Drop List" while 3 task\(s\) are still assigned/);
  assert.equal(blockedPayload.retryable, false);

  const stillPresent = db.prepare(
    'SELECT COUNT(*) AS count FROM lists WHERE id = ?',
  ).get('01966a3f-7c8b-7d4e-8f3a-000000000505') as { count: number };
  assert.equal(stillPresent.count, 1, 'Guarded delete_list should leave the list row intact');
  const blockedDeleteAuditRows = db.prepare(
    'SELECT COUNT(*) AS count FROM ai_changelog WHERE mcp_tool = ?',
  ).get('delete_list') as { count: number };
  assert.equal(blockedDeleteAuditRows.count, 0, 'Rejected delete_list should not append ai_changelog rows');
  const blockedDeleteOutboxRows = db.prepare(
    'SELECT COUNT(*) AS count FROM sync_outbox WHERE entity_type = ? AND entity_id = ?',
  ).get('list', '01966a3f-7c8b-7d4e-8f3a-000000000505') as { count: number };
  assert.equal(blockedDeleteOutboxRows.count, 0, 'Rejected delete_list should not enqueue sync_outbox rows');

  db.prepare(
    'DELETE FROM tasks WHERE list_id = ?',
  ).run('01966a3f-7c8b-7d4e-8f3a-000000000505');
  resetAuditTables(db);

  const deletedList = parseJsonContent<{
    deleted_list_id: string;
    previous: { id: string; name: string; icon: string | null; color: string | null };
    undo_token: string;
  }>(await harness.client.callTool({
    name: 'delete_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000505',
    },
  }));
  assert.equal(deletedList.deleted_list_id, '01966a3f-7c8b-7d4e-8f3a-000000000505');
  assert.equal(deletedList.previous.id, '01966a3f-7c8b-7d4e-8f3a-000000000505');
  assert.equal(deletedList.previous.name, 'Drop List');
  assert.equal(deletedList.previous.icon, 'trash');
  assert.equal(deletedList.previous.color, '#aa0000');

  const undoToken = JSON.parse(deletedList.undo_token) as {
    kind: string;
    mcp_tool: string;
    entity_id: string | null;
    expires_at: string;
    pre_entity_json: { id: string; name: string };
  };
  assert.equal(undoToken.kind, 'delete_list');
  assert.equal(undoToken.mcp_tool, 'delete_list');
  assert.equal(undoToken.entity_id, '01966a3f-7c8b-7d4e-8f3a-000000000505');
  assert.equal(undoToken.pre_entity_json.id, '01966a3f-7c8b-7d4e-8f3a-000000000505');
  assert.equal(undoToken.pre_entity_json.name, 'Drop List');
  assert.ok(undoToken.expires_at.length > 0, 'delete_list undo token should carry an expiry timestamp');

  const deletedRowCount = db.prepare(
    'SELECT COUNT(*) AS count FROM lists WHERE id = ?',
  ).get('01966a3f-7c8b-7d4e-8f3a-000000000505') as { count: number };
  assert.equal(deletedRowCount.count, 0, 'Successful delete_list should remove the list row');

  const deleteEnvelope = db.prepare(
    'SELECT operation FROM sync_outbox WHERE entity_type = ? AND entity_id = ?',
  ).get('list', '01966a3f-7c8b-7d4e-8f3a-000000000505') as { operation: string } | undefined;
  assert.ok(deleteEnvelope, 'delete_list should enqueue a list delete envelope');
  assert.equal(deleteEnvelope.operation, 'delete');

  const persistedUndoToken = db.prepare(
    'SELECT undo_token FROM ai_changelog WHERE mcp_tool = ? AND entity_type = ? AND entity_id = ?',
  ).get('delete_list', 'list', '01966a3f-7c8b-7d4e-8f3a-000000000505') as { undo_token: string | null } | undefined;
  assert.ok(persistedUndoToken, 'delete_list should persist an ai_changelog row');
  assert.equal(
    persistedUndoToken.undo_token,
    deletedList.undo_token,
    'delete_list should persist the exact returned undo_token in ai_changelog',
  );
});

test('delete_list rejects deleting the last remaining list', async (t) => {
  const harness = await createHarness('list-mutations-delete-last-list');
  t.after(async () => {
    await harness.cleanup();
  });

  const db = new Database(harness.dbPath);
  t.after(() => db.close());
  resetAuditTables(db);

  const lastListDelete = asToolResultPayload(await harness.client.callTool({
    name: 'delete_list',
    arguments: {
      id: 'inbox',
    },
  }));
  assert.equal(lastListDelete.isError, true, 'delete_list should reject deleting the last remaining list');
  const lastListPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(lastListDelete);
  assert.equal(lastListPayload.kind, 'validation');
  assert.match(lastListPayload.message, /Cannot delete the last list/);
  assert.equal(lastListPayload.retryable, false);

  const inboxStillPresent = db.prepare(
    'SELECT COUNT(*) AS count FROM lists WHERE id = ?',
  ).get('inbox') as { count: number };
  assert.equal(inboxStillPresent.count, 1, 'Last-list rejection should leave inbox in place');
  const deleteAuditRows = db.prepare(
    'SELECT COUNT(*) AS count FROM ai_changelog WHERE mcp_tool = ?',
  ).get('delete_list') as { count: number };
  assert.equal(deleteAuditRows.count, 0, 'Last-list rejection should not append ai_changelog rows');
  const deleteOutboxRows = db.prepare(
    'SELECT COUNT(*) AS count FROM sync_outbox WHERE entity_type = ? AND entity_id = ?',
  ).get('list', 'inbox') as { count: number };
  assert.equal(deleteOutboxRows.count, 0, 'Last-list rejection should not enqueue sync_outbox rows');
});

test('delete_list rejects cancelled-only assigned task rows before FK failure', async (t) => {
  const harness = await createHarness('list-mutations-delete-cancelled-only');
  t.after(async () => {
    await harness.cleanup();
  });

  const db = new Database(harness.dbPath);
  t.after(() => db.close());

  insertListSeed(db, {
    id: 'list-keep-cancelled',
    name: 'Keep Cancelled List',
  });
  insertListSeed(db, {
    id: '01966a3f-7c8b-7d4e-8f3a-000000000504',
    name: 'Drop Cancelled List',
  });
  insertTaskSeed(db, {
    id: 'task-cancelled-only',
    title: 'Cancelled task still assigned',
    list_id: '01966a3f-7c8b-7d4e-8f3a-000000000504',
    status: 'cancelled',
  });
  resetAuditTables(db);

  const cancelledOnlyDelete = asToolResultPayload(await harness.client.callTool({
    name: 'delete_list',
    arguments: {
      id: '01966a3f-7c8b-7d4e-8f3a-000000000504',
    },
  }));
  assert.equal(
    cancelledOnlyDelete.isError,
    true,
    'delete_list should reject cancelled-only task assignments before SQLite FK enforcement',
  );
  const cancelledOnlyPayload = parseJsonContent<{ kind: string; message: string; retryable: boolean }>(cancelledOnlyDelete);
  assert.equal(cancelledOnlyPayload.kind, 'validation');
  assert.match(
    cancelledOnlyPayload.message,
    /Cannot delete list "Drop Cancelled List" while 1 task\(s\) are still assigned/,
  );
  assert.equal(cancelledOnlyPayload.retryable, false);

  const cancelledListStillPresent = db.prepare(
    'SELECT COUNT(*) AS count FROM lists WHERE id = ?',
  ).get('01966a3f-7c8b-7d4e-8f3a-000000000504') as { count: number };
  assert.equal(cancelledListStillPresent.count, 1, 'Cancelled-only rejection should leave the list row intact');
  const cancelledDeleteAuditRows = db.prepare(
    'SELECT COUNT(*) AS count FROM ai_changelog WHERE mcp_tool = ?',
  ).get('delete_list') as { count: number };
  assert.equal(cancelledDeleteAuditRows.count, 0, 'Cancelled-only rejection should not append ai_changelog rows');
  const cancelledDeleteOutboxRows = db.prepare(
    'SELECT COUNT(*) AS count FROM sync_outbox WHERE entity_type = ? AND entity_id = ?',
  ).get('list', '01966a3f-7c8b-7d4e-8f3a-000000000504') as { count: number };
  assert.equal(cancelledDeleteOutboxRows.count, 0, 'Cancelled-only rejection should not enqueue sync_outbox rows');
});
