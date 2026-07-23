import assert from 'node:assert/strict';
import test from 'node:test';

import { createHarness, daysFromTodayYmd, parseJsonContent, parseTaskEnvelope } from '../shared';

test('add_daily_review and get_daily_review round-trip linked entities through MCP', async (t) => {
  const harness = await createHarness('reviews-and-preferences');
  t.after(async () => {
    await harness.cleanup();
  });

  const linkedList = parseJsonContent<{ id: string }>(await harness.client.callTool({
    name: 'create_list',
    arguments: { name: 'Review-linked list' },
  }));
  const linkedTask = parseTaskEnvelope<{ id: string }>(await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Task linked from daily review',
      list_id: linkedList.id,
    },
  }));
  const date = daysFromTodayYmd();

  const createdReview = parseJsonContent<{
    date: string;
    summary: string;
    linked_task_ids: string[];
    linked_list_ids: string[];
  }>(await harness.client.callTool({
    name: 'add_daily_review',
    arguments: {
      date,
      summary: 'Strong progress today',
      mood: 4,
      energy_level: 3,
      linked_task_ids: [linkedTask.id],
      linked_list_ids: [linkedList.id],
      wins: 'Covered missing MCP integration tests',
      blockers: 'None',
      learnings: 'Batching audits works better than single-point fixes',
      ai_synthesis: 'Momentum remained high across the session',
    },
  }));
  assert.equal(createdReview.date, date);
  assert.equal(createdReview.summary, 'Strong progress today');
  assert.deepEqual(createdReview.linked_task_ids, [linkedTask.id]);
  assert.deepEqual(createdReview.linked_list_ids, [linkedList.id]);

  const fetchedReview = parseJsonContent<{
    date: string;
    summary: string;
    linked_task_ids: string[];
    linked_list_ids: string[];
  }>(await harness.client.callTool({
    name: 'get_daily_review',
    arguments: { date },
  }));
  assert.equal(fetchedReview.date, date);
  assert.equal(fetchedReview.summary, 'Strong progress today');
  assert.deepEqual(fetchedReview.linked_task_ids, [linkedTask.id]);
  assert.deepEqual(fetchedReview.linked_list_ids, [linkedList.id]);
});

test('set_preference and get_preference keep typed values stable over direct MCP calls', async (t) => {
  const harness = await createHarness('preferences-contract-smoke');
  t.after(async () => {
    await harness.cleanup();
  });

  const setResult = parseJsonContent<{
    key: string;
    value: { enabled: boolean; labels: string[] };
    updated_at: string;
    undo_token: string;
  }>(await harness.client.callTool({
    name: 'set_preference',
    arguments: {
      key: 'dashboard_layout',
      value: {
        enabled: true,
        labels: ['alpha', 'beta'],
      },
    },
  }));
  assert.equal(setResult.key, 'dashboard_layout');
  assert.deepEqual(setResult.value, { enabled: true, labels: ['alpha', 'beta'] });
  assert.ok(setResult.updated_at, 'set_preference should return updated_at');
  assert.ok(setResult.undo_token, 'set_preference should expose an undo token');

  const getResult = parseJsonContent<{
    key: string;
    value: { enabled: boolean; labels: string[] };
    updated_at: string;
  }>(await harness.client.callTool({
    name: 'get_preference',
    arguments: {
      key: 'dashboard_layout',
    },
  }));
  assert.equal(getResult.key, 'dashboard_layout');
  assert.deepEqual(getResult.value, { enabled: true, labels: ['alpha', 'beta'] });
  assert.equal(getResult.updated_at, setResult.updated_at);
});
