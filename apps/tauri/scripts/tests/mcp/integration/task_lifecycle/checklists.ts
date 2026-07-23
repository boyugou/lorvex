import assert from 'node:assert/strict';
import test from 'node:test';

import { asToolResultPayload, createHarness, parseJsonContent, parseTaskEnvelope } from '../shared';

test('task checklist lifecycle tools return enriched checklist_items', async (t) => {
  const harness = await createHarness('task-checklists-lifecycle');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const created = parseTaskEnvelope<{ id: string; checklist_items: unknown[] }>(
    await client.callTool({
      name: 'create_task',
      arguments: { title: 'Checklist lifecycle task' },
    }),
  );
  assert.deepEqual(created.checklist_items, [], 'new tasks should return empty checklist_items');

  const addedFirst = parseJsonContent<{
    id: string;
    checklist_items: Array<{ id: string; text: string; completed_at: string | null }>;
  }>(await client.callTool({
    name: 'add_task_checklist_item',
    arguments: { id: created.id, text: 'First item' },
  }));
  assert.equal(addedFirst.checklist_items.length, 1);
  const firstItemId = addedFirst.checklist_items[0]!.id;

  const addedSecond = parseJsonContent<{
    checklist_items: Array<{ id: string; text: string }>;
  }>(await client.callTool({
    name: 'add_task_checklist_item',
    arguments: { id: created.id, text: 'Second item', position: 0 },
  }));
  assert.deepEqual(
    addedSecond.checklist_items.map((item) => item.text),
    ['Second item', 'First item'],
  );
  const secondItemId = addedSecond.checklist_items[0]!.id;

  const updated = parseJsonContent<{
    checklist_items: Array<{ id: string; text: string }>;
  }>(await client.callTool({
    name: 'update_task_checklist_item',
    arguments: { item_id: firstItemId, text: 'First item updated' },
  }));
  assert.deepEqual(
    updated.checklist_items.map((item) => item.text),
    ['Second item', 'First item updated'],
  );

  const toggled = parseJsonContent<{
    checklist_items: Array<{ id: string; completed_at: string | null }>;
  }>(await client.callTool({
    name: 'toggle_task_checklist_item',
    arguments: { item_id: secondItemId, completed: true },
  }));
  assert.ok(
    toggled.checklist_items.find((item) => item.id === secondItemId)?.completed_at,
    'toggle should set completed_at for explicit complete=true',
  );

  const reordered = parseJsonContent<{
    checklist_items: Array<{ id: string; text: string }>;
  }>(await client.callTool({
    name: 'reorder_task_checklist_items',
    arguments: { id: created.id, item_ids: [firstItemId, secondItemId] },
  }));
  assert.deepEqual(
    reordered.checklist_items.map((item) => item.id),
    [firstItemId, secondItemId],
  );

  const removed = parseJsonContent<{
    checklist_items: Array<{ id: string; text: string }>;
  }>(await client.callTool({
    name: 'remove_task_checklist_item',
    arguments: { item_id: secondItemId },
  }));
  assert.deepEqual(
    removed.checklist_items.map((item) => item.id),
    [firstItemId],
  );
});

test('reorder_task_checklist_items rejects incomplete item sets', async (t) => {
  const harness = await createHarness('task-checklists-reorder-invalid');
  t.after(async () => { await harness.cleanup(); });
  const { client } = harness;

  const created = parseTaskEnvelope<{ id: string }>(await client.callTool({
    name: 'create_task',
    arguments: { title: 'Checklist reorder validation task' },
  }));
  const first = parseJsonContent<{ checklist_items: Array<{ id: string }> }>(await client.callTool({
    name: 'add_task_checklist_item',
    arguments: { id: created.id, text: 'A' },
  }));
  const second = parseJsonContent<{ checklist_items: Array<{ id: string }> }>(await client.callTool({
    name: 'add_task_checklist_item',
    arguments: { id: created.id, text: 'B' },
  }));

  const itemIds = second.checklist_items.map((item) => item.id);
  const result = asToolResultPayload(await client.callTool({
    name: 'reorder_task_checklist_items',
    arguments: { id: created.id, item_ids: [itemIds[0]] },
  }));
  assert.equal(result.isError, true, 'invalid reorder should fail');
  assert.match(
    result.content?.[0]?.text ?? '',
    /requires exactly|must contain every checklist item/i,
  );
  assert.equal(first.checklist_items.length, 1);
});
