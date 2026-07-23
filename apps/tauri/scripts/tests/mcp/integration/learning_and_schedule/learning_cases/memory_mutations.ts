import assert from 'node:assert/strict';
import test from 'node:test';

import { createHarness, parseJsonContent } from '../../shared';

test('write_memory and restore_memory_revision round-trip through direct MCP tool calls', async (t) => {
  const harness = await createHarness('memory-mutations');
  t.after(async () => {
    await harness.cleanup();
  });

  const firstWrite = parseJsonContent<{
    key: string;
    content: string;
    updated_at: string;
  }>(await harness.client.callTool({
    name: 'write_memory',
    arguments: {
      key: 'project_brief',
      content: 'Initial assistant summary',
    },
  }));
  assert.equal(firstWrite.key, 'project_brief');
  assert.equal(firstWrite.content, 'Initial assistant summary');
  assert.ok(firstWrite.updated_at, 'write_memory should return updated_at');

  const secondWrite = parseJsonContent<{
    key: string;
    content: string;
  }>(await harness.client.callTool({
    name: 'write_memory',
    arguments: {
      key: 'project_brief',
      content: 'Revised assistant summary',
    },
  }));
  assert.equal(secondWrite.content, 'Revised assistant summary');

  const history = parseJsonContent<{
    key: string;
    count: number;
    revisions: Array<{
      id: string;
      content: string | null;
      operation: string;
    }>;
  }>(await harness.client.callTool({
    name: 'get_memory_history',
    arguments: {
      key: 'project_brief',
      limit: 10,
    },
  }));
  assert.equal(history.key, 'project_brief');
  assert.ok(history.count >= 2, `expected at least 2 revisions, got ${history.count}`);
  const originalRevision = history.revisions.find((revision) => revision.content === 'Initial assistant summary');
  assert.ok(originalRevision, 'history should include the original revision content');

  const restored = parseJsonContent<{
    restored: boolean;
    key: string;
    from_revision_id: string;
    new_revision_id: string;
  }>(await harness.client.callTool({
    name: 'restore_memory_revision',
    arguments: {
      revision_id: originalRevision!.id,
    },
  }));
  assert.equal(restored.restored, true);
  assert.equal(restored.key, 'project_brief');
  assert.equal(restored.from_revision_id, originalRevision!.id);
  assert.notEqual(
    restored.new_revision_id,
    originalRevision!.id,
    'restoring should append a fresh revision instead of reusing the source revision id',
  );

  const readBack = parseJsonContent<{
    key: string;
    content: string | null;
    updated_at: string | null;
  }>(await harness.client.callTool({
    name: 'read_memory',
    arguments: {
      key: 'project_brief',
    },
  }));
  assert.equal(readBack.key, 'project_brief');
  assert.ok(readBack.content?.includes('Initial assistant summary'));
  assert.ok(readBack.updated_at, 'restored memory should remain timestamped');
});
