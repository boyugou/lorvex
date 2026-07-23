import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createHarness,
  parseJsonContent,
} from '../../shared';

test('get_list supports bounded responses with truncation metadata', async (t) => {
  const harness = await createHarness('list-bounds');
  t.after(async () => {
    await harness.cleanup();
  });

  const listResult = await harness.client.callTool({
    name: 'create_list',
    arguments: {
      name: 'Large List',
    },
  });
  const list = parseJsonContent<{ id: string }>(listResult);

  for (let i = 0; i < 8; i += 1) {
    await harness.client.callTool({
      name: 'create_task',
      arguments: {
        title: `bounded-task-${i}`,
        list_id: list.id,
      },
    });
  }

  const bounded = await harness.client.callTool({
    name: 'get_list',
    arguments: {
      id: list.id,
      limit: 3,
    },
  });
  const boundedPayload = parseJsonContent<{
    id: string;
    tasks: Array<{ id: string; title: string }>;
    total_matching: number;
    truncated: boolean;
    limit: number;
  }>(bounded);
  assert.equal(boundedPayload.id, list.id);
  assert.equal(boundedPayload.limit, 3);
  assert.equal(boundedPayload.tasks.length, 3);
  assert.equal(boundedPayload.truncated, true);
  assert.ok(boundedPayload.total_matching >= 8, 'Expected total matching count to include all list tasks');
});
