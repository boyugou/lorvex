import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  createHarness,
  parseTaskEnvelope,
  TEST_AGENT_NAME,
} from './shared';

test('representative write tool persists data and records ai_changelog/sync_outbox', async (t) => {
  const harness = await createHarness('write-path');
  t.after(async () => {
    await harness.cleanup();
  });

  const createTaskResult = await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Write MCP integration tests',
      raw_input: 'create task from integration test',
      priority: 2,
    },
  });
  const createdTask = parseTaskEnvelope<{ id: string; title: string; status: string }>(createTaskResult);

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const taskRow = db.prepare('SELECT id, title, status, raw_input FROM tasks WHERE id = ?')
    .get(createdTask.id) as { id: string; title: string; status: string; raw_input: string } | undefined;
  assert.ok(taskRow, 'Expected create_task to write a task row');
  assert.equal(taskRow.title, 'Write MCP integration tests');
  assert.equal(taskRow.status, 'open');
  assert.equal(taskRow.raw_input, 'create task from integration test');

  const changelogRow = db.prepare(`
    SELECT operation, entity_type, entity_id, initiated_by, mcp_tool
    FROM ai_changelog
    WHERE entity_id = ?
    ORDER BY timestamp DESC
    LIMIT 1
  `).get(createdTask.id) as {
    operation: string;
    entity_type: string;
    entity_id: string;
    initiated_by: string;
    mcp_tool: string;
  } | undefined;
  assert.ok(changelogRow, 'Expected ai_changelog record for create_task');
  assert.equal(changelogRow.operation, 'create');
  assert.equal(changelogRow.entity_type, 'task');
  assert.equal(changelogRow.entity_id, createdTask.id);
  assert.equal(changelogRow.initiated_by, TEST_AGENT_NAME);
  assert.equal(changelogRow.mcp_tool, 'create_task');

  const syncEventRow = db.prepare(`
    SELECT entity_type, entity_id, operation, payload, synced_at
    FROM sync_outbox
    WHERE entity_id = ?
    ORDER BY created_at DESC
    LIMIT 1
  `).get(createdTask.id) as {
    entity_type: string;
    entity_id: string;
    operation: string;
    payload: string;
    synced_at: string | null;
  } | undefined;
  assert.ok(syncEventRow, 'Expected sync_outbox record for create_task');
  assert.equal(syncEventRow.entity_type, 'task');
  assert.equal(syncEventRow.entity_id, createdTask.id);
  assert.equal(syncEventRow.operation, 'upsert');
  assert.equal(syncEventRow.synced_at, null);
  const payload = JSON.parse(syncEventRow.payload) as { id?: string; title?: string };
  assert.equal(payload.id, createdTask.id);
  assert.equal(payload.title, 'Write MCP integration tests');
});
