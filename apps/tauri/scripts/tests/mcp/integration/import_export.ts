import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  asToolResultPayload,
  createHarness,
  parseJsonContent,
  requireRecordValue,
} from './shared';

test('export/import roundtrip preserves representative records', async (t) => {
  const harness = await createHarness('roundtrip');
  t.after(async () => {
    await harness.cleanup();
  });

  const listResult = await harness.client.callTool({
    name: 'create_list',
    arguments: {
      name: 'Roundtrip List',
      color: '#4F8EF7',
    },
  });
  const createdList = parseJsonContent<{ id: string; name: string }>(listResult);

  const taskResult = await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Roundtrip Task',
      list_id: createdList.id,
      raw_input: 'source task',
    },
  });
  const createdTask = parseJsonContent<{ task: { id: string; list_id: string | null } }>(taskResult).task;

  // Export to ZIP file
  const exportResult = await harness.client.callTool({
    name: 'export_all_data',
    arguments: {
      output_path: 'roundtrip',
    },
  });
  const exportSummary = parseJsonContent<{
    export_path: string;
    format_version: number;
    entity_counts?: Record<string, number>;
  }>(exportResult);
  assert.ok(exportSummary.export_path, 'Expected export_path in result');
  assert.match(exportSummary.export_path, /[\\/]exports[\\/]roundtrip\.zip$/);
  assert.ok(existsSync(exportSummary.export_path), 'Expected ZIP file to exist');
  assert.equal(exportSummary.format_version, 1);

  // Import the same archive back into the same server (self-roundtrip)
  // This verifies the ZIP format is valid and can be re-imported.
  // Since the data already exists, entities will be "updated" or "skipped".
  const importResult = asToolResultPayload(await harness.client.callTool({
    name: 'import_data',
    arguments: {
      file_path: exportSummary.export_path,
    },
  }));
  assert.notStrictEqual(importResult.isError, true,
    `Expected import to succeed, got: ${JSON.stringify(importResult.content).slice(0, 300)}\nMCP stderr: ${harness.stderr().slice(-500)}`);
  const importSummary = parseJsonContent<{
    entities_created: number;
    entities_updated: number;
    entities_skipped: number;
  }>(importResult);
  // Self-import: entities are either updated or skipped (same version), not created
  const totalProcessed = importSummary.entities_created + importSummary.entities_updated + importSummary.entities_skipped;
  assert.ok(totalProcessed >= 2, 'Expected at least list + task processed in roundtrip');

  // Verify data still intact
  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const task = db.prepare('SELECT id, title, list_id, raw_input FROM tasks WHERE id = ?')
    .get(createdTask.id) as { id: string; title: string; list_id: string | null; raw_input: string | null } | undefined;
  assert.ok(task, 'Expected task to still exist after roundtrip');
  assert.equal(task.title, 'Roundtrip Task');
  assert.equal(task.list_id, createdList.id);

  const list = db.prepare('SELECT id, name, color FROM lists WHERE id = ?')
    .get(createdList.id) as { id: string; name: string; color: string | null } | undefined;
  assert.ok(list, 'Expected list to still exist after roundtrip');
  assert.equal(list.name, 'Roundtrip List');
});

test('export_all_data produces a valid ZIP archive', async (t) => {
  const harness = await createHarness('export-valid');
  t.after(async () => {
    await harness.cleanup();
  });

  // Create a task so there's something to export
  await harness.client.callTool({
    name: 'create_task',
    arguments: { title: 'Export test task' },
  });

  const exportResult = await harness.client.callTool({
    name: 'export_all_data',
    arguments: { output_path: 'test-export.zip' },
  });
  const payload = asToolResultPayload(exportResult);
  assert.notStrictEqual(payload.isError, true, 'Expected export to succeed');

  const summary = parseJsonContent<{
    export_path: string;
    format_version: number;
  }>(exportResult);
  assert.match(summary.export_path, /[\\/]exports[\\/]test-export\.zip$/);
  assert.ok(existsSync(summary.export_path), 'Expected ZIP file to exist');
  assert.equal(summary.format_version, 1);
});

test('export_all_data supports scoped export categories', async (t) => {
  const harness = await createHarness('export-scoped');
  t.after(async () => {
    await harness.cleanup();
  });

  const listResult = await harness.client.callTool({
    name: 'create_list',
    arguments: { name: 'Scoped Export List' },
  });
  const createdList = parseJsonContent<{ id: string }>(listResult);

  await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Scoped Export Task',
      list_id: createdList.id,
    },
  });

  const exportResult = await harness.client.callTool({
    name: 'export_all_data',
    arguments: {
      output_path: 'tasks-only.zip',
      scope_categories: ['tasks'],
    },
  });
  const payload = asToolResultPayload(exportResult);
  assert.notStrictEqual(payload.isError, true, 'Expected scoped export to succeed');

  const summary = parseJsonContent<{
    export_path: string;
    format_version: number;
    scope_kind: 'full' | 'scoped';
    scope_categories: string[];
    entity_counts: Record<string, number>;
  }>(exportResult);
  assert.match(summary.export_path, /[\\/]exports[\\/]tasks-only\.zip$/);
  assert.ok(existsSync(summary.export_path), 'Expected scoped ZIP file to exist');
  assert.equal(summary.format_version, 1);
  assert.equal(summary.scope_kind, 'scoped');
  assert.deepEqual(summary.scope_categories, ['tasks']);
  assert.ok(
    requireRecordValue(summary.entity_counts, 'task', 'Expected task export count') >= 1,
    'Expected tasks in scoped export',
  );
  assert.ok(
    requireRecordValue(summary.entity_counts, 'list', 'Expected list export count') >= 1,
    'Expected task list closure in scoped export',
  );
});

test('export_all_data normalizes custom output paths to ZIP archives', async (t) => {
  const harness = await createHarness('export-zip-path');
  t.after(async () => {
    await harness.cleanup();
  });

  const exportResult = await harness.client.callTool({
    name: 'export_all_data',
    arguments: { output_path: 'snapshot-backup' },
  });
  const payload = asToolResultPayload(exportResult);
  assert.notStrictEqual(payload.isError, true, 'Expected export to succeed');

  const summary = parseJsonContent<{ export_path: string }>(exportResult);
  assert.match(summary.export_path, /[\\/]exports[\\/]snapshot-backup\.zip$/);
  assert.ok(existsSync(summary.export_path), 'Expected normalized ZIP file to exist');
});

test('import_data rejects non-ZIP paths before store import', async (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'lorvex-import-nonzip-'));
  const filePath = join(dir, 'not-a-zip.txt');
  writeFileSync(filePath, 'plain text');
  const harness = await createHarness('import-nonzip');
  t.after(async () => {
    await harness.cleanup();
    rmSync(dir, { recursive: true, force: true });
  });

  const result = asToolResultPayload(await harness.client.callTool({
    name: 'import_data',
    arguments: { file_path: filePath },
  }));
  assert.equal(result.isError, true, 'Expected non-ZIP import to fail');
  const message = JSON.stringify(result.content);
  assert.match(message, /\.zip archive|valid ZIP archive/);
});
