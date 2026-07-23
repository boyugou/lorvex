import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  asToolResultPayload,
  createHarness,
  getFirstTextContent,
  requireRecordValue,
  resetBehaviorTables,
  seedScaleDataset,
} from '../shared';

test('scale payload budgets remain bounded at 1k and 10k datasets', async (t) => {
  const harness = await createHarness('scale-payload-budget');
  t.after(async () => {
    await harness.cleanup();
  });

  const db = new Database(harness.dbPath, { fileMustExist: true });
  t.after(() => db.close());
  const payloadBudgetBytesByTool: Record<string, number> = {
    list_tasks: 450_000,
    search_tasks: 450_000,
    get_deferred_tasks: 350_000,
    get_todays_tasks: 700_000,
    get_upcoming_tasks: 700_000,
    get_list: 700_000,
  };

  const latencyBudgetMsByTool: Record<string, number> = {
    list_tasks: 8_000,
    search_tasks: 8_000,
    get_deferred_tasks: 8_000,
    get_todays_tasks: 8_000,
    get_upcoming_tasks: 8_000,
    get_list: 8_000,
  };

  const calls: Array<{ name: string; arguments: Record<string, unknown> }> = [
    { name: 'list_tasks', arguments: { list_id: 'list-scale-budget', status: 'all' } },
    { name: 'search_tasks', arguments: { query: 'Scale task', status: 'all' } },
    { name: 'get_deferred_tasks', arguments: { list_id: 'list-scale-budget' } },
    { name: 'get_todays_tasks', arguments: {} },
    { name: 'get_upcoming_tasks', arguments: { days: 14 } },
    { name: 'get_list', arguments: { id: 'list-scale-budget' } },
  ];

  for (const datasetSize of [1_000, 10_000]) {
    resetBehaviorTables(db);
    seedScaleDataset(db, datasetSize, 'list-scale-budget');

    for (const call of calls) {
      const started = performance.now();
      const result = asToolResultPayload(await harness.client.callTool({
        name: call.name,
        arguments: call.arguments,
      }));
      const elapsedMs = performance.now() - started;
      const text = getFirstTextContent(result);
      const payloadBytes = Buffer.byteLength(text, 'utf8');
      assert.notStrictEqual(result.isError, true, `[${datasetSize}] ${call.name} returned MCP error payload`);
      const latencyBudgetMs = requireRecordValue(latencyBudgetMsByTool, call.name, `latency budget for ${call.name}`);
      const payloadBudgetBytes = requireRecordValue(payloadBudgetBytesByTool, call.name, `payload budget for ${call.name}`);
      assert.ok(
        elapsedMs <= latencyBudgetMs,
        `[${datasetSize}] ${call.name} latency ${elapsedMs.toFixed(1)}ms exceeded budget ${latencyBudgetMs}ms`,
      );
      assert.ok(
        payloadBytes <= payloadBudgetBytes,
        `[${datasetSize}] ${call.name} payload ${payloadBytes}B exceeded budget ${payloadBudgetBytes}B`,
      );

      const payload = JSON.parse(text) as Record<string, unknown>;
      if (call.name === 'list_tasks' || call.name === 'search_tasks' || call.name === 'get_deferred_tasks') {
        const limit = Number(payload.limit);
        const returned = Number(payload.returned);
        const totalMatching = Number(payload.total_matching);
        const truncated = Boolean(payload.truncated);
        assert.ok(Number.isFinite(limit) && limit > 0, `[${datasetSize}] ${call.name} missing positive limit`);
        assert.ok(Number.isFinite(returned) && returned <= limit, `[${datasetSize}] ${call.name} returned exceeds limit`);
        assert.equal(truncated, totalMatching > returned, `[${datasetSize}] ${call.name} truncation metadata mismatch`);
      }

      if (call.name === 'get_todays_tasks') {
        const summary = payload.summary as Record<string, unknown>;
        assert.ok(summary, `[${datasetSize}] get_todays_tasks missing summary`);
        assert.equal(payload.returned, summary.count);
        assert.equal(payload.total_matching, summary.total_matching);
      }

      if (call.name === 'get_upcoming_tasks') {
        assert.equal(payload.returned, payload.total_tasks);
        const totalMatching = Number(payload.total_matching);
        const returned = Number(payload.returned);
        assert.equal(Boolean(payload.truncated), totalMatching > returned);
      }

      if (call.name === 'get_list') {
        const limit = Number(payload.limit);
        const returned = Number(payload.returned);
        const totalMatching = Number(payload.total_matching);
        assert.ok(returned <= limit);
        assert.equal(Boolean(payload.truncated), totalMatching > returned);
      }
    }
  }
});
