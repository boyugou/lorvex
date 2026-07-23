import test from 'node:test';
import assert from 'node:assert/strict';

import {
  classifyTaskRelativeSection,
  isTaskInRelativeSections,
  taskEffectiveActionDate,
} from '../../../app/src/lib/tasks/dayBuckets';
import { compareTaskByDueThenPriority } from '../../../app/src/lib/tasks/taskComparators';
import type { Task } from '../../../app/src/lib/ipc';

function makeTask(overrides: Partial<Task> = {}): Task {
  return {
    id: overrides.id ?? 'task-1',
    title: overrides.title ?? 'Task',
    body: null,
    raw_input: null,
    ai_notes: null,
    status: overrides.status ?? 'open',
    list_id: overrides.list_id ?? 'list-1',
    tags: null,
    priority: overrides.priority ?? null,
    due_date: overrides.due_date ?? null,
    due_time: overrides.due_time ?? null,
    estimated_minutes: null,
    recurrence: null,
    spawned_from: null,
    recurrence_group_id: null,
    canonical_occurrence_date: null,
    version: '0000000000000_0000_00000000',
    created_at: overrides.created_at ?? '2026-04-01T00:00:00Z',
    updated_at: overrides.updated_at ?? '2026-04-01T00:00:00Z',
    completed_at: null,
    last_deferred_at: null,
    last_defer_reason: null,
    lateness_state: overrides.lateness_state ?? null,
    planned_date: overrides.planned_date ?? null,
    defer_count: 0,
  };
}

test('taskEffectiveActionDate prefers planned_date over due_date', () => {
  assert.equal(
    taskEffectiveActionDate(makeTask({ planned_date: '2026-04-07', due_date: '2026-04-10' })),
    '2026-04-07',
  );
  assert.equal(taskEffectiveActionDate(makeTask({ due_date: '2026-04-10' })), '2026-04-10');
  assert.equal(taskEffectiveActionDate(makeTask()), null);
});

test('classifyTaskRelativeSection uses lateness/effective action date semantics', () => {
  const today = '2026-04-04';

  assert.equal(
    classifyTaskRelativeSection(
      makeTask({ due_date: '2026-04-03', lateness_state: 'overdue_unhandled', planned_date: '2026-04-09' }),
      today,
    ),
    'overdue',
  );
  assert.equal(
    classifyTaskRelativeSection(makeTask({ planned_date: '2026-04-03', due_date: '2026-04-08' }), today),
    'today',
  );
  assert.equal(
    classifyTaskRelativeSection(makeTask({ planned_date: '2026-04-05', due_date: '2026-04-08' }), today),
    'tomorrow',
  );
  assert.equal(
    classifyTaskRelativeSection(makeTask({ due_date: '2026-04-09' }), today),
    'this_week',
  );
  assert.equal(
    classifyTaskRelativeSection(makeTask({ due_date: '2026-04-20' }), today),
    'later',
  );
  assert.equal(classifyTaskRelativeSection(makeTask(), today), 'no_date');
});

test('isTaskInRelativeSections lets surfaces share one canonical bucket owner', () => {
  const today = '2026-04-04';

  assert.equal(
    isTaskInRelativeSections(
      makeTask({ due_date: '2026-04-03', lateness_state: 'overdue_acknowledged' }),
      today,
      ['overdue', 'today'],
    ),
    true,
  );
  assert.equal(
    isTaskInRelativeSections(
      makeTask({ planned_date: '2026-04-04', due_date: '2026-04-09' }),
      today,
      ['overdue', 'today'],
    ),
    true,
  );
  assert.equal(
    isTaskInRelativeSections(
      makeTask({ due_date: '2026-04-10' }),
      today,
      ['overdue', 'today', 'tomorrow', 'this_week', 'no_date'],
    ),
    true,
  );
  assert.equal(
    isTaskInRelativeSections(
      makeTask({ due_date: '2026-04-20' }),
      today,
      ['overdue', 'today', 'tomorrow', 'this_week', 'no_date'],
    ),
    false,
  );
});

test('compareTaskByDueThenPriority keeps older deadlines ahead of higher-priority newer ones', () => {
  const older = makeTask({ id: 'older', due_date: '2026-04-01', priority: 3 });
  const newerUrgent = makeTask({ id: 'newer', due_date: '2026-04-02', priority: 1 });

  const ordered = [newerUrgent, older].sort(compareTaskByDueThenPriority);
  assert.deepEqual(
    ordered.map((task) => task.id),
    ['older', 'newer'],
  );
});
