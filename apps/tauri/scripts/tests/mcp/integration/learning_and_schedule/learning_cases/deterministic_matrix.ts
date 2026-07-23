import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  createHarness,
  insertListSeed,
  insertTaskSeed,
  isoDaysAgo,
  daysFromTodayYmd,
  parseJsonContent,
  resetBehaviorTables,
} from '../../shared';

import type { LearningInsightsPayload } from './shared';

test('analyze_task_patterns deterministic matrix covers severity thresholds, top_n, and window filtering', async (t) => {
  const harness = await createHarness('learning-insights-deterministic-matrix');
  t.after(async () => {
    await harness.cleanup();
  });
  const db = new Database(harness.dbPath, { fileMustExist: true });
  t.after(() => db.close());

  const overdueDate = daysFromTodayYmd(-1);
  const recentUpdatedAt = isoDaysAgo(2);
  const staleUpdatedAt = isoDaysAgo(10);
  const oldUpdatedAt = isoDaysAgo(45);

  const learningCases: Array<{
    name: string;
    args: Record<string, unknown>;
    setup: (seedDb: Database.Database) => void;
    assertPayload: (payload: LearningInsightsPayload, seedDb: Database.Database) => void;
  }> = [
    {
      name: 'no-signal baseline',
      args: { window_days: 30, top_n: 3 },
      setup: () => {},
      assertPayload: (payload) => {
        assert.equal(payload.metrics.frequently_deferred, 0);
        assert.equal(payload.metrics.stalled_lists, 0);
        assert.equal(payload.metrics.overdue_backlog, 0);
        assert.equal(payload.insights.length, 0);
        assert.equal(payload.source_refs.length, 0);
      },
    },
    {
      name: 'deferred severity=medium at count 4',
      args: { window_days: 30, top_n: 10 },
      setup: (seedDb) => {
        for (let i = 0; i < 4; i += 1) {
          insertTaskSeed(seedDb, {
            id: `li2-deferred-${i}`,
            title: `Deferred ${i}`,
            status: 'open',
            defer_count: 3,
            updated_at: recentUpdatedAt,
          });
        }
      },
      assertPayload: (payload) => {
        assert.equal(payload.metrics.frequently_deferred, 4);
        const deferredInsight = payload.insights.find((entry) => entry.type === 'frequently_deferred');
        assert.ok(deferredInsight, 'Expected frequently_deferred insight');
        assert.equal(deferredInsight.severity, 'medium');
        assert.equal(payload.representative_samples.frequently_deferred.length, 4);
      },
    },
    {
      name: 'deferred severity=high and top_n capping with out-of-window exclusions',
      args: { window_days: 30, top_n: 3 },
      setup: (seedDb) => {
        for (let i = 0; i < 9; i += 1) {
          insertTaskSeed(seedDb, {
            id: `li3-deferred-${i}`,
            title: `Deferred high ${i}`,
            status: 'open',
            defer_count: 3,
            updated_at: recentUpdatedAt,
          });
        }
        insertTaskSeed(seedDb, {
          id: 'li3-old-deferred',
          title: 'Old deferred outside window',
          status: 'open',
          defer_count: 4,
          updated_at: oldUpdatedAt,
        });
      },
      assertPayload: (payload) => {
        assert.equal(payload.metrics.frequently_deferred, 9);
        const deferredInsight = payload.insights.find((entry) => entry.type === 'frequently_deferred');
        assert.ok(deferredInsight, 'Expected frequently_deferred insight');
        assert.equal(deferredInsight.severity, 'high');
        assert.equal(payload.representative_samples.frequently_deferred.length, 3);
        assert.equal(deferredInsight.source_refs.length, 3);
      },
    },
    {
      name: 'stalled_lists severity=medium at count 2',
      args: { window_days: 30, top_n: 5 },
      setup: (seedDb) => {
        insertListSeed(seedDb, { id: 'li4-list-a', name: 'List A' });
        insertListSeed(seedDb, { id: 'li4-list-b', name: 'List B' });
        insertTaskSeed(seedDb, {
          id: 'li4-task-a',
          title: 'Stalled A',
          list_id: 'li4-list-a',
          status: 'open',
          updated_at: staleUpdatedAt,
        });
        insertTaskSeed(seedDb, {
          id: 'li4-task-b',
          title: 'Stalled B',
          list_id: 'li4-list-b',
          status: 'open',
          updated_at: staleUpdatedAt,
        });
      },
      assertPayload: (payload) => {
        assert.equal(payload.metrics.stalled_lists, 2);
        const stalledInsight = payload.insights.find((entry) => entry.type === 'stalled_lists');
        assert.ok(stalledInsight, 'Expected stalled_lists insight');
        assert.equal(stalledInsight.severity, 'medium');
        assert.equal(payload.representative_samples.stalled_lists.length, 2);
      },
    },
    {
      name: 'overdue_backlog severity=high at count 15 with top_n sample cap',
      args: { window_days: 30, top_n: 4 },
      setup: (seedDb) => {
        for (let i = 0; i < 15; i += 1) {
          insertTaskSeed(seedDb, {
            id: `li5-overdue-${i}`,
            title: `Overdue ${i}`,
            status: 'open',
            due_date: overdueDate,
            updated_at: recentUpdatedAt,
          });
        }
      },
      assertPayload: (payload) => {
        assert.equal(payload.metrics.overdue_backlog, 15);
        const overdueInsight = payload.insights.find((entry) => entry.type === 'overdue_backlog');
        assert.ok(overdueInsight, 'Expected overdue_backlog insight');
        assert.equal(overdueInsight.severity, 'high');
        assert.equal(payload.representative_samples.overdue_backlog.length, 4);
        assert.equal(overdueInsight.source_refs.length, 4);
      },
    },
  ];

  for (const scenario of learningCases) {
    resetBehaviorTables(db);
    scenario.setup(db);
    const response = await harness.client.callTool({
      name: 'analyze_task_patterns',
      arguments: scenario.args,
    });
    const payload = parseJsonContent<LearningInsightsPayload>(response);
    assert.equal(payload.window_days, scenario.args.window_days ?? 30, `[${scenario.name}] window_days mismatch`);
    assert.equal(payload.top_n, scenario.args.top_n ?? 5, `[${scenario.name}] top_n mismatch`);
    scenario.assertPayload(payload, db);
  }

  assert.equal(learningCases.length, 5, 'Expected five deterministic task-pattern-analysis scenarios in this matrix');
});
