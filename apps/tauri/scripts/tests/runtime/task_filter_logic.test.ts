import assert from 'node:assert/strict';
import test from 'node:test';

import {
  pruneSelectedTaskFilterTags,
  replaceSelectedTaskFilterTags,
  resolveTaskFiltersPersistence,
  selectedTaskFilterTagsPersistenceArray,
} from '../../../app/src/lib/tasks/useTaskFilters';

test('pruneSelectedTaskFilterTags drops tags that are no longer available', () => {
  const next = pruneSelectedTaskFilterTags(
    new Set(['alpha', 'beta', 'gamma']),
    ['beta', 'gamma', 'delta'],
  );

  assert.deepEqual([...next], ['beta', 'gamma']);
});

test('pruneSelectedTaskFilterTags preserves selection identity when every tag is still present', () => {
  const selected = new Set(['alpha', 'beta']);
  const next = pruneSelectedTaskFilterTags(selected, ['beta', 'alpha', 'gamma']);

  assert.deepEqual([...next], ['alpha', 'beta']);
});

test('replaceSelectedTaskFilterTags atomically rebuilds the selected tag set', () => {
  const next = replaceSelectedTaskFilterTags(['focus', 'focus', 'deep-work']);

  assert.deepEqual([...next], ['focus', 'deep-work']);
});

test('saved-query tag replacement can be pruned against the current available tags immediately', () => {
  const next = pruneSelectedTaskFilterTags(
    replaceSelectedTaskFilterTags(['focus', 'missing', 'deep-work']),
    ['deep-work', 'focus'],
  );

  assert.deepEqual([...next], ['focus', 'deep-work']);
});

test('task filter persistence resolution depends on scalar keys instead of descriptor identity', () => {
  const first = resolveTaskFiltersPersistence({
    filterListIdKey: 'allTasks.filterListId',
    selectedTagsKey: 'allTasks.selectedTags',
  });
  const second = resolveTaskFiltersPersistence({
    filterListIdKey: 'allTasks.filterListId',
    selectedTagsKey: 'allTasks.selectedTags',
  });

  assert.deepEqual(first, second);
  assert.equal(first.hasPersistence, true);
  assert.equal(resolveTaskFiltersPersistence().hasPersistence, false);
});

test('persisted selected-tag writes preserve array identity for equal sorted contents', () => {
  const previous = ['deep-work', 'focus'];
  const equal = selectedTaskFilterTagsPersistenceArray(previous, new Set(['focus', 'deep-work']));
  const changed = selectedTaskFilterTagsPersistenceArray(previous, new Set(['focus']));

  assert.equal(equal, previous);
  assert.deepEqual(changed, ['focus']);
  assert.notEqual(changed, previous);
});
