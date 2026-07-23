import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  createHarness,
  parseJsonContent,
  parseTaskEnvelope,
} from '../../shared';
import { daysFromTodayYmd } from '../../shared/time';

import type { LearningInsightsPayload } from './shared';

test('analyze_task_patterns returns actionable signals with source refs', async (t) => {
  const harness = await createHarness('learning-insights');
  t.after(async () => {
    await harness.cleanup();
  });

  const deferredCreate = await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Repeatedly deferred task',
    },
  });
  const deferredTask = parseTaskEnvelope<{ id: string }>(deferredCreate);

  // Defer the task 3 times using defer_task (which increments defer_count
  // and keeps status as 'open' with planned_date set).
  // canonical UTC-anchored helper; previous inline helper
  // used setDate (local-tz) so the seed + server resolver disagreed on
  // midnight boundaries.
  for (let i = 0; i < 3; i += 1) {
    await harness.client.callTool({
      name: 'defer_task',
      arguments: {
        id: deferredTask.id,
        until_date: daysFromTodayYmd(i + 1),
        reason: `Deferral round ${i + 1}`,
      },
    });
  }

  const overdueCreate = await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Overdue task signal',
      due_date: '2000-01-01',
    },
  });
  const overdueTask = parseTaskEnvelope<{ id: string }>(overdueCreate);

  const insightsResult = await harness.client.callTool({
    name: 'analyze_task_patterns',
    arguments: {
      window_days: 30,
      top_n: 3,
    },
  });

  const insights = parseJsonContent<LearningInsightsPayload>(insightsResult);

  assert.equal(insights.window_days, 30);
  assert.equal(insights.top_n, 3);
  assert.ok(insights.insights.some((entry) => entry.type === 'frequently_deferred'));
  assert.ok(insights.insights.some((entry) => entry.type === 'overdue_backlog'));
  assert.ok(insights.source_refs.includes(`task:${deferredTask.id}`));
  assert.ok(insights.source_refs.includes(`task:${overdueTask.id}`));
});

test('analyze_task_patterns is a pure read that does not persist memory', async (t) => {
  const harness = await createHarness('learning-insights-no-persist-default');
  t.after(async () => {
    await harness.cleanup();
  });

  const insightsResult = await harness.client.callTool({
    name: 'analyze_task_patterns',
    arguments: {
      window_days: 14,
      top_n: 3,
    },
  });

  const insights = parseJsonContent<{
    window_days: number;
    top_n: number;
  }>(insightsResult);

  assert.equal(insights.window_days, 14);
  assert.equal(insights.top_n, 3);

  const db = new Database(harness.dbPath, { readonly: true, fileMustExist: true });
  t.after(() => db.close());

  const memoryRows = db.prepare('SELECT COUNT(*) as n FROM memories').get() as { n: number };
  assert.equal(memoryRows.n, 0, 'Expected no memory rows from pure-read analyze_task_patterns');

  const memoryLogs = db.prepare(`
    SELECT COUNT(*) as n
    FROM ai_changelog
    WHERE entity_type = 'memory'
  `).get() as { n: number };
  assert.equal(memoryLogs.n, 0, 'Expected no memory changelog entries from pure-read analyze_task_patterns');
});
