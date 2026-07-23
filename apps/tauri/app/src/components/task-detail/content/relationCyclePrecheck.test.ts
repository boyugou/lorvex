import { describe, expect, it } from 'vitest';
import type { Task } from '@/lib/ipc/tasks/models';
import {
  buildRelationGraphSnapshot,
  wouldCreateCycle,
} from './relationCyclePrecheck';

function task(id: string, dependsOn: string[] | null = null): Task {
  return {
    id,
    title: id,
    body: null,
    raw_input: null,
    ai_notes: null,
    status: 'open',
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

describe('relation cycle precheck', () => {
  it('flags self-edge as cycle in both directions', () => {
    const snap = buildRelationGraphSnapshot([task('a')], 'a');
    expect(wouldCreateCycle(snap, 'depends_on', 'a')).toBe(true);
    expect(wouldCreateCycle(snap, 'blocks', 'a')).toBe(true);
  });

  it('detects a 2-task cycle in the depends_on direction', () => {
    // b already depends on a → adding "a depends_on b" forms a→b→a.
    const snap = buildRelationGraphSnapshot([task('a'), task('b', ['a'])], 'a');
    expect(wouldCreateCycle(snap, 'depends_on', 'b')).toBe(true);
  });

  it('detects a 2-task cycle in the blocks direction', () => {
    // a depends on b → adding "a blocks b" (b depends on a) forms b→a→b.
    const snap = buildRelationGraphSnapshot([task('a', ['b']), task('b')], 'a');
    expect(wouldCreateCycle(snap, 'blocks', 'b')).toBe(true);
  });

  it('does not flag a safe edge', () => {
    const snap = buildRelationGraphSnapshot([task('a'), task('b'), task('c')], 'a');
    expect(wouldCreateCycle(snap, 'depends_on', 'b')).toBe(false);
    expect(wouldCreateCycle(snap, 'blocks', 'c')).toBe(false);
  });

  it('detects a transitive cycle through a chain', () => {
    // c→b→a; adding "a depends_on c" closes the loop.
    const snap = buildRelationGraphSnapshot(
      [task('a'), task('b', ['a']), task('c', ['b'])],
      'a',
    );
    expect(wouldCreateCycle(snap, 'depends_on', 'c')).toBe(true);
  });

  it('tolerates missing tasks in the snapshot (orphan candidate)', () => {
    const snap = buildRelationGraphSnapshot([task('a')], 'a');
    expect(wouldCreateCycle(snap, 'depends_on', 'orphan')).toBe(false);
  });
});
