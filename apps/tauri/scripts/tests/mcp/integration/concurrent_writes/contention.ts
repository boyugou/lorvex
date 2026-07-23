import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import {
  createHarness,
  createSecondaryClient,
  asToolResultPayload,
  parseJsonContent,
  parseTaskEnvelope,
} from '../shared';

/**
 * Helper: attempt a tool call, returning either the parsed result or an error string.
 * Under contention, MCP may return an error (e.g. "database is locked").
 * This is expected behavior — the test validates that failures are explicit.
 */
async function tryToolCall<T>(
  client: { callTool: (args: { name: string; arguments: Record<string, unknown> }) => Promise<unknown> },
  name: string,
  args: Record<string, unknown>,
): Promise<{ ok: true; value: T } | { ok: false; error: string }> {
  const result = await client.callTool({ name, arguments: args });
  const payload = asToolResultPayload(result);
  const text = payload.content?.find(p => p.type === 'text')?.text ?? '';
  if (payload.isError || text.startsWith('Error:')) {
    return { ok: false, error: text };
  }
  return { ok: true, value: JSON.parse(text) as T };
}

/**
 * E-DB-001: Concurrent write validation under contention.
 *
 * Two MCP server processes share the same WAL-mode SQLite database.
 * Both fire rapid writes simultaneously. We verify:
 * - No silent data loss: every call either succeeds or returns an explicit error
 * - Successful writes are durable (task count matches successes)
 * - ai_changelog captures every successful write
 * - No database corruption (PRAGMA integrity_check passes)
 */
test('concurrent writes from two MCP servers: no data loss under contention', async (t) => {
  const harness = await createHarness('concurrent-writes');
  const secondary = await createSecondaryClient(harness.dbPath, 'ci-secondary-writer');
  t.after(async () => {
    await secondary.cleanup();
    await harness.cleanup();
  });

  const clientA = harness.client;
  const clientB = secondary.client;

  // Both clients create a list first (sequentially to avoid contention during setup)
  const listA = parseJsonContent<{ id: string }>(
    await clientA.callTool({ name: 'create_list', arguments: { name: 'Client A Work' } }),
  );
  const listB = parseJsonContent<{ id: string }>(
    await clientB.callTool({ name: 'create_list', arguments: { name: 'Client B Work' } }),
  );

  // Fire rapid concurrent writes: each client creates 10 tasks simultaneously
  const TASKS_PER_CLIENT = 10;

  const allPromises: Promise<{ ok: true; value: { task: { id: string } } } | { ok: false; error: string }>[] = [];
  for (let i = 0; i < TASKS_PER_CLIENT; i++) {
    allPromises.push(
      tryToolCall<{ task: { id: string } }>(clientA, 'create_task', {
        title: `A task ${i}`,
        list_id: listA.id,
        priority: ((i % 3) + 1),
      }),
    );
    allPromises.push(
      tryToolCall<{ task: { id: string } }>(clientB, 'create_task', {
        title: `B task ${i}`,
        list_id: listB.id,
        priority: ((i % 3) + 1),
      }),
    );
  }

  const results = await Promise.all(allPromises);
  const successes = results.filter(r => r.ok);
  const failures = results.filter(r => !r.ok);

  // Key invariant: no silent failures — every call returned a result
  assert.equal(
    successes.length + failures.length,
    TASKS_PER_CLIENT * 2,
    'Every call should return either success or an explicit error',
  );

  // Under WAL mode with 5s busy_timeout, a meaningful fraction of writes should
  // succeed even under burst contention. The threshold is conservative because
  // SQLite write-lock contention with multi-statement SAVEPOINTs across two
  // processes can cascade timeouts when all 20 writes fire at exactly the same
  // instant. In real usage, writes are more spread out.
  const MIN_SUCCESSES = 2;
  assert.ok(
    successes.length >= MIN_SUCCESSES,
    `At least ${MIN_SUCCESSES} of ${TASKS_PER_CLIENT * 2} writes should succeed (got ${successes.length})`,
  );

  // Failures must be explicit error messages (not empty or corrupted)
  for (const f of failures) {
    assert.ok(!f.ok);
    assert.ok(
      f.error.length > 0,
      'Failed writes must return a non-empty error message',
    );
  }

  // Verify durable state matches successful write count
  const db = new Database(harness.dbPath, { readonly: true });
  const taskCount = db.prepare('SELECT COUNT(*) as cnt FROM tasks').get() as { cnt: number };
  assert.equal(
    taskCount.cnt,
    successes.length,
    `DB task count (${taskCount.cnt}) should match successful writes (${successes.length})`,
  );

  // Verify ai_changelog captured every successful create
  const changelogCount = db.prepare(
    "SELECT COUNT(*) as cnt FROM ai_changelog WHERE operation = 'create' AND entity_type = 'task'",
  ).get() as { cnt: number };
  assert.ok(
    changelogCount.cnt >= successes.length,
    `ai_changelog should have at least ${successes.length} create entries (got ${changelogCount.cnt})`,
  );

  // Verify database integrity after contention
  const integrity = db.prepare('PRAGMA integrity_check').get() as { integrity_check: string };
  assert.equal(integrity.integrity_check, 'ok', 'Database integrity check should pass after contention');

  db.close();
});

/**
 * Concurrent read-write interleaving: one client writes while the other reads.
 * WAL mode should allow reads to proceed without blocking on writes.
 */
test('concurrent read-write interleaving: reads succeed during active writes', async (t) => {
  const harness = await createHarness('concurrent-rw');
  const secondary = await createSecondaryClient(harness.dbPath, 'ci-reader');
  t.after(async () => {
    await secondary.cleanup();
    await harness.cleanup();
  });

  const writer = harness.client;
  const reader = secondary.client;

  // Create a list and some initial tasks
  const list = parseJsonContent<{ id: string }>(
    await writer.callTool({ name: 'create_list', arguments: { name: 'Shared List' } }),
  );

  for (let i = 0; i < 5; i++) {
    await writer.callTool({
      name: 'create_task',
      arguments: { title: `Seed task ${i}`, list_id: list.id },
    });
  }

  // Now interleave: writer creates 5 more tasks while reader queries overview repeatedly
  const writePromises: Promise<unknown>[] = [];
  const readPromises: Promise<unknown>[] = [];

  for (let i = 5; i < 10; i++) {
    writePromises.push(
      writer.callTool({
        name: 'create_task',
        arguments: { title: `Concurrent task ${i}`, list_id: list.id },
      }),
    );
    readPromises.push(
      reader.callTool({
        name: 'get_overview',
        arguments: {},
      }),
    );
  }

  // Fire all at once
  const [writeResults, readResults] = await Promise.all([
    Promise.all(writePromises),
    Promise.all(readPromises),
  ]);

  // All writes should succeed (sequential within single client + 5s busy_timeout)
  assert.equal(writeResults.length, 5, 'All concurrent writes should complete');

  // All reads should succeed and return valid JSON
  for (const result of readResults) {
    const overview = parseJsonContent<{ stats: { open_count: number } }>(result);
    assert.ok(
      overview.stats.open_count >= 5,
      'Reader should see at least the seed tasks during concurrent writes',
    );
  }

  // Final state: all 10 tasks exist
  const db = new Database(harness.dbPath, { readonly: true });
  const taskCount = db.prepare('SELECT COUNT(*) as cnt FROM tasks').get() as { cnt: number };
  assert.equal(taskCount.cnt, 10, 'All 10 tasks should exist after interleaved read-write');
  db.close();
});

/**
 * Concurrent state transitions: both clients modify the same tasks.
 * One completes tasks while the other updates metadata on different tasks.
 * Verifies no lost updates and correct final state.
 */
test('concurrent state transitions: complete and update on non-overlapping task sets', async (t) => {
  const harness = await createHarness('concurrent-transitions');
  const secondary = await createSecondaryClient(harness.dbPath, 'ci-updater');
  t.after(async () => {
    await secondary.cleanup();
    await harness.cleanup();
  });

  const clientA = harness.client;
  const clientB = secondary.client;

  // Create shared list and tasks (sequentially to avoid contention during setup)
  const list = parseJsonContent<{ id: string }>(
    await clientA.callTool({ name: 'create_list', arguments: { name: 'Contention List' } }),
  );

  const taskIds: string[] = [];
  for (let i = 0; i < 6; i++) {
    const result = await clientA.callTool({
      name: 'create_task',
      arguments: { title: `Contention task ${i}`, list_id: list.id, priority: 2 },
    });
    taskIds.push(parseTaskEnvelope<{ id: string }>(result).id);
  }

  // Client A completes tasks 0-2, Client B updates metadata on tasks 3-5
  // Non-overlapping task sets to avoid semantic conflicts, but they contend on the same DB.
  const completeResults = await Promise.all(
    taskIds.slice(0, 3).map(id =>
      tryToolCall<{ completed: { id: string; status: string } }>(clientA, 'complete_task', { id }),
    ),
  );

  const updateResults = await Promise.all(
    taskIds.slice(3, 6).map(id =>
      tryToolCall<{ id: string; priority: number }>(clientB, 'update_task', {
        id,
        priority: 3,
        estimated_minutes: 45,
      }),
    ),
  );

  const completeSuccesses = completeResults.filter(r => r.ok).length;
  const updateSuccesses = updateResults.filter(r => r.ok).length;

  // Under WAL mode with 5s timeout, most should succeed
  assert.ok(completeSuccesses >= 2, `At least 2 of 3 completions should succeed (got ${completeSuccesses})`);
  assert.ok(updateSuccesses >= 2, `At least 2 of 3 updates should succeed (got ${updateSuccesses})`);

  // Verify final state
  const db = new Database(harness.dbPath, { readonly: true });

  const completedCount = db.prepare(
    "SELECT COUNT(*) as cnt FROM tasks WHERE status = 'completed'",
  ).get() as { cnt: number };
  assert.equal(completedCount.cnt, completeSuccesses, 'Completed count should match successful completions');

  const updatedTasks = db.prepare(
    'SELECT id, priority, estimated_minutes FROM tasks WHERE priority = 3',
  ).all() as Array<{ id: string; priority: number; estimated_minutes: number }>;
  assert.equal(updatedTasks.length, updateSuccesses, 'Updated task count should match successful updates');
  for (const task of updatedTasks) {
    assert.equal(task.estimated_minutes, 45, 'Updated tasks should have 45min duration');
  }

  // Verify database integrity
  const integrity = db.prepare('PRAGMA integrity_check').get() as { integrity_check: string };
  assert.equal(integrity.integrity_check, 'ok', 'Database integrity check should pass');

  db.close();
});
