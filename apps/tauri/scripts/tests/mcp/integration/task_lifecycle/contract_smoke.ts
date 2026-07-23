import assert from 'node:assert/strict';
import test from 'node:test';
import Database from 'better-sqlite3';

import { createHarness, parseJsonContent, parseTaskEnvelope } from '../shared';

test('set_recurrence and get_dependency_graph have direct MCP integration coverage', async (t) => {
  const harness = await createHarness('task-contract-smoke');
  t.after(async () => {
    await harness.cleanup();
  });

  const blocker = parseTaskEnvelope<{ id: string }>(await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Block quoted blocker',
      due_date: '2026-05-05',
    },
  }));
  const dependent = parseTaskEnvelope<{ id: string; depends_on: string[] | null }>(await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Dependent task',
      depends_on: [blocker.id],
    },
  }));
  assert.deepEqual(dependent.depends_on, [blocker.id]);

  const recurring = parseTaskEnvelope<{
    id: string;
    recurrence: string | null;
  }>(await harness.client.callTool({
    name: 'set_recurrence',
    arguments: {
      id: blocker.id,
      freq: 'weekly',
      interval: 2,
      byday: ['MO', 'WE'],
      count: 4,
    },
  }));
  assert.equal(recurring.id, blocker.id);
  assert.equal(
    recurring.recurrence,
    '{"BYDAY":["MO","WE"],"COUNT":4,"FREQ":"WEEKLY","INTERVAL":2}',
    'set_recurrence should return the normalized recurrence JSON string',
  );

  const graph = parseJsonContent<{
    node_count: number;
    edge_count: number;
    nodes: Array<{ id: string; title?: string }>;
    edges: Array<{ from: string; to: string }>;
    blocked: string[];
    roots: string[];
    leaf_blockers: string[];
    truncated: boolean;
  }>(await harness.client.callTool({
    name: 'get_dependency_graph',
    arguments: {
      task_id: dependent.id,
      limit_nodes: 20,
      limit_edges: 20,
    },
  }));
  assert.equal(graph.node_count, 2);
  assert.equal(graph.edge_count, 1);
  assert.deepEqual(graph.edges, [{ from: dependent.id, to: blocker.id }]);
  assert.ok(graph.blocked.includes(dependent.id), 'dependent should be marked blocked');
  assert.ok(graph.roots.includes(blocker.id), 'unblocked blocker should appear as the graph root');
  assert.ok(graph.leaf_blockers.includes(blocker.id), 'blocker should appear as a leaf blocker');
  assert.equal(graph.truncated, false);
  assert.deepEqual(
    graph.nodes.map((node) => node.id).sort(),
    [blocker.id, dependent.id].sort(),
  );
});

test('permanent_delete_task deletes an archived task and returns its previous snapshot', async (t) => {
  const harness = await createHarness('permanent-delete-smoke');
  t.after(async () => {
    await harness.cleanup();
  });

  const task = parseTaskEnvelope<{ id: string; title: string }>(await harness.client.callTool({
    name: 'create_task',
    arguments: {
      title: 'Archived duplicate to delete',
    },
  }));

  const db = new Database(harness.dbPath);
  t.after(() => {
    db.close();
  });
  db.prepare(
    "UPDATE tasks SET archived_at = '2026-04-21T12:00:00Z', updated_at = '2026-04-21T12:00:00Z' WHERE id = ?",
  ).run(task.id);

  const deleted = parseJsonContent<{
    id: string;
    deleted: boolean;
    previous: { id: string; title: string; archived_at: string | null } | null;
  }>(await harness.client.callTool({
    name: 'permanent_delete_task',
    arguments: {
      id: task.id,
    },
  }));
  assert.equal(deleted.id, task.id);
  assert.equal(deleted.deleted, true);
  assert.equal(deleted.previous?.id, task.id);
  assert.equal(deleted.previous?.title, 'Archived duplicate to delete');
  assert.equal(deleted.previous?.archived_at, '2026-04-21T12:00:00Z');

  const remaining = db.prepare('SELECT COUNT(*) AS n FROM tasks WHERE id = ?').get(task.id) as { n: number };
  assert.equal(remaining.n, 0, 'permanent_delete_task should remove the archived task row');
});
