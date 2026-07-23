import { describe, expect, it } from 'vitest';
import type { Task } from '@/lib/ipc/tasks/models';
import {
  buildClusters,
  isDependencyGraphActiveTask,
  isDependencyGraphTerminalTask,
} from './clustering';

function task(id: string, status: Task['status'], dependsOn: string[] | null = null): Task {
  return {
    id,
    title: id,
    body: null,
    raw_input: null,
    ai_notes: null,
    status,
    list_id: 'list',
    tags: null,
    checklist_items: null,
    priority: null,
    due_date: null,
    due_time: null,
    estimated_minutes: null,
    recurrence: null,
    recurrence_exceptions: null,
    depends_on: dependsOn,
    spawned_from: null,
    recurrence_group_id: null,
    canonical_occurrence_date: null,
    recurrence_instance_key: null,
    version: '0000000000000_0000_7465737464657663',
    created_at: '2026-05-09T00:00:00Z',
    updated_at: '2026-05-09T00:00:00Z',
    completed_at: null,
    last_deferred_at: null,
    last_defer_reason: null,
    planned_date: null,
    defer_count: 0,
    archived_at: null,
  };
}

describe('dependency graph status predicates', () => {
  it.each(['open', 'someday'] as const)('treats %s tasks as active', (status) => {
    expect(isDependencyGraphActiveTask(task(status, status))).toBe(true);
    expect(isDependencyGraphTerminalTask(task(status, status))).toBe(false);
  });

  it.each(['completed', 'cancelled'] as const)('treats %s tasks as terminal', (status) => {
    expect(isDependencyGraphTerminalTask(task(status, status))).toBe(true);
    expect(isDependencyGraphActiveTask(task(status, status))).toBe(false);
  });
});

describe('buildClusters terminal dependency math', () => {
  it.each(['completed', 'cancelled'] as const)(
    'does not count tasks blocked by a %s dependency',
    (terminalStatus) => {
      const clusters = buildClusters([
        task('dependency', terminalStatus),
        task('successor', 'open', ['dependency']),
      ]);

      expect(clusters).toHaveLength(1);
      expect(clusters[0]?.blockedCount).toBe(0);
    },
  );

  it('counts open and someday dependencies as blocking active successors', () => {
    const clusters = buildClusters([
      task('open-dependency', 'open'),
      task('someday-dependency', 'someday'),
      task('blocked-by-open', 'open', ['open-dependency']),
      task('blocked-by-someday', 'open', ['someday-dependency']),
    ]);

    expect(clusters).toHaveLength(2);
    expect(clusters.reduce((sum, cluster) => sum + cluster.blockedCount, 0)).toBe(2);
  });

  it('does not count a cancelled successor as blocked', () => {
    const clusters = buildClusters([
      task('dependency', 'open'),
      task('cancelled-successor', 'cancelled', ['dependency']),
    ]);

    expect(clusters).toHaveLength(1);
    expect(clusters[0]?.blockedCount).toBe(0);
  });
});
