import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildListGroupedTaskSections,
  partitionTasksByListOwnership,
  resolveTaskListGroupingMeta,
} from '../../../app/src/lib/tasks/listOwnership';
import type { ListWithCount, Task } from '../../../app/src/lib/ipc/tasks';

function makeTask(id: string, listId: string): Task {
  return {
    id,
    title: id,
    body: null,
    status: 'open',
    list_id: listId,
    planned_date: null,
    due_date: null,
    due_time: null,
    completed_at: null,
    cancelled_at: null,
    estimated_minutes: null,
    source_kind: 'manual',
    source_metadata_json: null,
    recurrence_rule: null,
    recurrence_timezone: null,
    next_recurrence_at: null,
    last_recurrence_at: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    priority: null,
    priority_effective: 4,
    ai_notes: null,
    checklist_progress: null,
    tags: [],
    checklist_items: [],
    reminders: [],
    subtasks: [],
    has_subtasks: false,
    blocked_by_count: 0,
    blocking_count: 0,
    list_name: null,
    list_icon: null,
    calendar_event_count: 0,
    memory_count: 0,
    dependency_count: 0,
  } as Task;
}

function makeList(id: string): ListWithCount {
  return {
    id,
    name: id,
    icon: null,
    color: null,
    position: 0,
    task_count: 0,
    completed_count: 0,
    cancelled_count: 0,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  };
}

test('partitionTasksByListOwnership fails open while the list inventory is still unresolved', () => {
  const tasks = [makeTask('task-a', 'list-a'), makeTask('task-b', 'missing-list')];
  const result = partitionTasksByListOwnership(tasks, undefined);

  assert.deepEqual(result.authoredTasks.map((task) => task.id), ['task-a', 'task-b']);
  assert.deepEqual(result.repairTasks, []);
  assert.notStrictEqual(result.authoredTasks, tasks);
});

test('partitionTasksByListOwnership routes unknown loaded list ids into repairTasks', () => {
  const tasks = [
    makeTask('task-a', 'list-a'),
    makeTask('task-b', 'missing-list'),
  ];
  const result = partitionTasksByListOwnership(tasks, [makeList('list-a')]);

  assert.deepEqual(result.authoredTasks.map((task) => task.id), ['task-a']);
  assert.deepEqual(result.repairTasks.map((task) => task.id), ['task-b']);
});

test('resolveTaskListGroupingMeta falls back to the task list id while the inventory is unresolved', () => {
  const task = makeTask('task-a', 'list-a');
  assert.deepEqual(resolveTaskListGroupingMeta(task, undefined), {
    id: 'list-a',
    name: 'list-a',
    icon: null,
  });
});

test('resolveTaskListGroupingMeta prefers loaded canonical list metadata and fails closed for missing loaded lists', () => {
  const task = makeTask('task-a', 'list-a');

  assert.deepEqual(resolveTaskListGroupingMeta(task, [makeList('list-a')]), {
    id: 'list-a',
    name: 'list-a',
    icon: null,
  });
  assert.equal(resolveTaskListGroupingMeta(task, []), null);
});

test('buildListGroupedTaskSections shows a temporary loading bucket while the list inventory is unresolved', () => {
  const tasks = [makeTask('task-a', 'list-a'), makeTask('task-b', 'list-b')];
  const sections = buildListGroupedTaskSections(tasks, undefined, {
    loadingLabel: 'Loading…',
    sortTasks: (sectionTasks) => [...sectionTasks].reverse(),
  });

  assert.deepEqual(sections, [{
    key: 'list-loading',
    title: 'Loading…',
    tasks: [tasks[1], tasks[0]],
  }]);
});

test('buildListGroupedTaskSections uses canonical loaded lists and drops tasks whose loaded list is missing', () => {
  const tasks = [makeTask('task-a', 'list-a'), makeTask('task-b', 'missing-list')];
  const sections = buildListGroupedTaskSections(tasks, [makeList('list-a')], {
    loadingLabel: 'Loading…',
    sortTasks: (sectionTasks) => sectionTasks,
  });

  assert.deepEqual(sections, [{
    key: 'list-list-a',
    title: 'list-a',
    tasks: [tasks[0]],
  }]);
});
