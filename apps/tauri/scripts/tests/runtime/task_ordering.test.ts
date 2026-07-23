import assert from 'node:assert/strict';
import test from 'node:test';

import {
  compareTaskByActionDateThenPriority,
  compareTaskByPlannedDateThenPriority,
  compareTaskByPriorityThenDue,
} from '../../../app/src/lib/tasks/taskComparators';
import { buildStatusSections } from '../../../app/src/components/all-tasks/useAllTasksController';
import { rankFallbackFocusTask } from '../../../app/src/components/today-view/taskOrdering';
import { resolveCompletedSectionSortDirection, sortTasks } from '../../../app/src/lib/tasks/taskSorting';
import type { Task } from '../../../shared/src/types';

function makeTask(overrides: Partial<Task>): Task {
  return {
    id: overrides.id ?? 'task-id',
    title: overrides.title ?? 'Task',
    body: null,
    raw_input: null,
    ai_notes: null,
    status: 'open',
    list_id: overrides.list_id ?? 'list-1',
    tags: null,
    priority: overrides.priority ?? null,
    due_date: overrides.due_date ?? null,
    due_time: overrides.due_time ?? null,
    estimated_minutes: null,
    recurrence: null,
    depends_on: null,
    spawned_from: null,
    recurrence_group_id: null,
    canonical_occurrence_date: null,
    version: 'v1',
    created_at: '2026-04-04T00:00:00Z',
    updated_at: '2026-04-04T00:00:00Z',
    completed_at: null,
    last_deferred_at: null,
    last_defer_reason: null,
    planned_date: null,
    defer_count: 0,
    ...overrides,
  };
}

test('task ordering prefers priority before due date', () => {
  const laterDueHigherPriority = makeTask({
    id: 'p1-later',
    title: 'High importance later',
    priority: 1,
    due_date: '2026-04-10',
  });
  const soonerDueLowerPriority = makeTask({
    id: 'p3-sooner',
    title: 'Lower importance sooner',
    priority: 3,
    due_date: '2026-04-05',
  });

  const ordered = [soonerDueLowerPriority, laterDueHigherPriority].sort(compareTaskByPriorityThenDue);
  assert.deepEqual(ordered.map((task) => task.id), ['p1-later', 'p3-sooner']);
});

test('task ordering treats null priority as the canonical lowest-priority bucket after explicit P3', () => {
  const explicitP3 = makeTask({
    id: 'explicit-p3',
    priority: 3,
    title: 'Explicit P3',
  });
  const nullPriority = makeTask({
    id: 'null-priority',
    priority: null,
    title: 'Null priority',
  });

  const ordered = [nullPriority, explicitP3].sort(compareTaskByPriorityThenDue);
  assert.deepEqual(ordered.map((task) => task.id), ['explicit-p3', 'null-priority']);
});

test('task ordering mirrors the Rust canonical order: priority, due date, then id', () => {
  const idFirstLaterTime = makeTask({
    id: 'a',
    title: 'Alpha',
    priority: 2,
    due_date: '2026-04-06',
    due_time: '17:00',
  });
  const idSecondEarlierTime = makeTask({
    id: 'b',
    title: 'Beta',
    priority: 2,
    due_date: '2026-04-06',
    due_time: '09:00',
  });
  const undated = makeTask({
    id: 'c',
    title: 'Gamma',
    priority: 2,
    due_date: null,
  });

  const ordered = [undated, idSecondEarlierTime, idFirstLaterTime].sort(compareTaskByPriorityThenDue);
  assert.deepEqual(ordered.map((task) => task.id), ['a', 'b', 'c']);
});

test('task ordering keeps undated tasks after the largest valid due date', () => {
  const undatedLowerId = makeTask({
    id: 'a-undated',
    priority: 2,
    due_date: null,
  });
  const largestValidDateHigherId = makeTask({
    id: 'z-largest-date',
    priority: 2,
    due_date: '9999-12-31',
  });

  const ordered = [undatedLowerId, largestValidDateHigherId].sort(compareTaskByPriorityThenDue);
  assert.deepEqual(ordered.map((task) => task.id), ['z-largest-date', 'a-undated']);
});

test('sortTasks priority uses the same canonical planning comparator', () => {
  const highPriorityLater = makeTask({
    id: 'priority-later',
    priority: 1,
    due_date: '2026-04-10',
  });
  const lowerPrioritySooner = makeTask({
    id: 'priority-sooner',
    priority: 3,
    due_date: '2026-04-05',
  });

  const ordered = sortTasks([lowerPrioritySooner, highPriorityLater], 'priority');
  assert.deepEqual(ordered.map((task) => task.id), ['priority-later', 'priority-sooner']);
});

test('sortTasks actionDate follows effective action date before importance', () => {
  const actionSoonerLowerPriority = makeTask({
    id: 'action-sooner',
    priority: 3,
    planned_date: '2026-04-05',
    due_date: '2026-04-12',
  });
  const actionLaterHigherPriority = makeTask({
    id: 'action-later',
    priority: 1,
    planned_date: '2026-04-08',
    due_date: '2026-04-08',
  });

  const ordered = sortTasks([actionLaterHigherPriority, actionSoonerLowerPriority], 'actionDate');
  assert.deepEqual(ordered.map((task) => task.id), ['action-sooner', 'action-later']);
});

test('compareTaskByActionDateThenPriority breaks same action-day ties by real deadline before due time', () => {
  const plannedTodayDueLaterWithTime = makeTask({
    id: 'planned-today-later-deadline',
    planned_date: '2026-04-10',
    due_date: '2026-04-12',
    due_time: '09:00',
    priority: 1,
  });
  const dueTodayNoTime = makeTask({
    id: 'due-today',
    planned_date: null,
    due_date: '2026-04-10',
    due_time: null,
    priority: 3,
  });

  const ordered = [plannedTodayDueLaterWithTime, dueTodayNoTime].sort(compareTaskByActionDateThenPriority);
  assert.deepEqual(ordered.map((task) => task.id), ['due-today', 'planned-today-later-deadline']);
});

test('sortTasks dueDate uses due time and stable identity instead of date-only sorting', () => {
  const lateSameDay = makeTask({
    id: 'late',
    title: 'Late',
    due_date: '2026-04-06',
    due_time: '17:00',
    priority: 2,
  });
  const earlySameDay = makeTask({
    id: 'early',
    title: 'Early',
    due_date: '2026-04-06',
    due_time: '09:00',
    priority: 2,
  });
  const titleTieA = makeTask({
    id: 'a-id',
    title: 'Same title',
    due_date: '2026-04-06',
    due_time: '12:00',
    priority: 2,
  });
  const titleTieB = makeTask({
    id: 'b-id',
    title: 'Same title',
    due_date: '2026-04-06',
    due_time: '12:00',
    priority: 2,
  });

  const ordered = sortTasks([lateSameDay, titleTieB, earlySameDay, titleTieA], 'dueDate');
  assert.deepEqual(ordered.map((task) => task.id), ['early', 'a-id', 'b-id', 'late']);
});

test('compareTaskByPlannedDateThenPriority falls through to deadline risk and identity for same planned date', () => {
  const dueSooner = makeTask({
    id: 'due-sooner',
    planned_date: '2026-04-10',
    due_date: '2026-04-11',
    due_time: '09:00',
    priority: 3,
  });
  const dueLaterHigherPriority = makeTask({
    id: 'due-later',
    planned_date: '2026-04-10',
    due_date: '2026-04-12',
    due_time: '08:00',
    priority: 1,
  });

  const ordered = [dueLaterHigherPriority, dueSooner].sort(compareTaskByPlannedDateThenPriority);
  assert.deepEqual(ordered.map((task) => task.id), ['due-sooner', 'due-later']);
});

test('sortTasks title/completedAt/createdAt stay deterministic on ties', () => {
  const titleTieA = makeTask({ id: 'a-id', title: 'Same title' });
  const titleTieB = makeTask({ id: 'b-id', title: 'Same title' });

  assert.deepEqual(
    sortTasks([titleTieB, titleTieA], 'title').map((task) => task.id),
    ['a-id', 'b-id'],
  );

  const completedTieA = makeTask({
    id: 'a-completed',
    title: 'Same completed',
    completed_at: '2026-04-06T12:00:00Z',
  });
  const completedTieB = makeTask({
    id: 'b-completed',
    title: 'Same completed',
    completed_at: '2026-04-06T12:00:00Z',
  });
  assert.deepEqual(
    sortTasks([completedTieB, completedTieA], 'completedAt').map((task) => task.id),
    ['a-completed', 'b-completed'],
  );

  const createdTieA = makeTask({
    id: 'a-created',
    title: 'Same created',
    created_at: '2026-04-06T12:00:00Z',
  });
  const createdTieB = makeTask({
    id: 'b-created',
    title: 'Same created',
    created_at: '2026-04-06T12:00:00Z',
  });
  assert.deepEqual(
    sortTasks([createdTieB, createdTieA], 'createdAt').map((task) => task.id),
    ['a-created', 'b-created'],
  );

  const newestCompleted = makeTask({
    id: 'newest-completed',
    completed_at: '2026-04-07T12:00:00Z',
  });
  const oldestCompleted = makeTask({
    id: 'oldest-completed',
    completed_at: '2026-04-06T12:00:00Z',
  });
  assert.deepEqual(
    sortTasks([oldestCompleted, newestCompleted], 'completedAt', 'desc').map((task) => task.id),
    ['newest-completed', 'oldest-completed'],
  );

  const newestCreated = makeTask({
    id: 'newest-created',
    created_at: '2026-04-07T12:00:00Z',
  });
  const oldestCreated = makeTask({
    id: 'oldest-created',
    created_at: '2026-04-06T12:00:00Z',
  });
  assert.deepEqual(
    sortTasks([oldestCreated, newestCreated], 'createdAt', 'desc').map((task) => task.id),
    ['newest-created', 'oldest-created'],
  );
});

test('non-title sorts use id-only tie-breaks instead of silently re-sorting equal rows by title', () => {
  const dueTieA = makeTask({
    id: 'a-due',
    title: 'Zulu',
    due_date: '2026-04-06',
    due_time: '12:00',
    priority: 2,
  });
  const dueTieB = makeTask({
    id: 'b-due',
    title: 'Alpha',
    due_date: '2026-04-06',
    due_time: '12:00',
    priority: 2,
  });
  assert.deepEqual(
    sortTasks([dueTieB, dueTieA], 'dueDate').map((task) => task.id),
    ['a-due', 'b-due'],
  );

  const completedTieA = makeTask({
    id: 'a-completed-id',
    title: 'Zulu complete',
    completed_at: '2026-04-06T12:00:00Z',
  });
  const completedTieB = makeTask({
    id: 'b-completed-id',
    title: 'Alpha complete',
    completed_at: '2026-04-06T12:00:00Z',
  });
  assert.deepEqual(
    sortTasks([completedTieB, completedTieA], 'completedAt').map((task) => task.id),
    ['a-completed-id', 'b-completed-id'],
  );
});

test('completed status sections keep newest-first when the surface is still on default sorting', () => {
  assert.equal(resolveCompletedSectionSortDirection('default', 'asc'), 'desc');
  assert.equal(resolveCompletedSectionSortDirection('completedAt', 'asc'), 'asc');
  assert.equal(resolveCompletedSectionSortDirection('completedAt', 'desc'), 'desc');

  const cancelledOlder = makeTask({
    id: 'cancelled-older',
    status: 'cancelled',
    completed_at: '2026-04-06T12:00:00Z',
  });
  const cancelledNewer = makeTask({
    id: 'cancelled-newer',
    status: 'cancelled',
    completed_at: '2026-04-07T12:00:00Z',
  });
  const completedOlder = makeTask({
    id: 'completed-older',
    status: 'completed',
    completed_at: '2026-04-06T12:00:00Z',
  });
  const completedNewer = makeTask({
    id: 'completed-newer',
    status: 'completed',
    completed_at: '2026-04-07T12:00:00Z',
  });

  const sections = buildStatusSections(
    [completedOlder, cancelledOlder, completedNewer, cancelledNewer],
    'default',
    'asc',
    {
      open: 'Open',
      someday: 'Someday',
      cancelled: 'Cancelled',
      completed: 'Completed',
    },
  );

  assert.deepEqual(
    sections.find((section) => section.key === 'cancelled')?.tasks.map((task) => task.id),
    ['cancelled-newer', 'cancelled-older'],
  );
  assert.deepEqual(
    sections.find((section) => section.key === 'completed')?.tasks.map((task) => task.id),
    ['completed-newer', 'completed-older'],
  );
});

test('rankFallbackFocusTask respects canonical relative sections instead of raw due_date only', () => {
  const today = '2026-04-04';
  const plannedTodayDueLater = makeTask({
    id: 'planned-today',
    planned_date: today,
    due_date: '2026-04-10',
  });
  const dueTomorrow = makeTask({
    id: 'due-tomorrow',
    due_date: '2026-04-05',
  });

  assert.ok(
    rankFallbackFocusTask(plannedTodayDueLater, today) < rankFallbackFocusTask(dueTomorrow, today),
    'tasks planned for today should rank ahead of merely upcoming work even if their due_date is later',
  );
});
