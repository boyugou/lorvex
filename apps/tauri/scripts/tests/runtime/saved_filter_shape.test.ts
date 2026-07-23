import assert from 'node:assert/strict';
import test from 'node:test';

import {
  deserializeViewFilters,
  readSavedFilterEnum,
  readSavedFilterNumberEnum,
  serializeViewFilters,
} from '../../../app/src/lib/tasks/savedFilterShape';

test('deserializeViewFilters fails closed on malformed field types and preserves only valid entries', () => {
  const decoded = deserializeViewFilters(JSON.stringify({
    search: 42,
    listId: { nope: true },
    priority: 999,
    tags: ['focus', 7, 'deep-work', 'focus'],
    showCompleted: 'yes',
    showCancelled: false,
    groupBy: ['status'],
    sortKey: 'priority',
    sortDirection: 'desc',
    horizonDays: -7,
  }));

  assert.deepEqual(decoded, {
    tags: ['focus', 'deep-work'],
    showCancelled: false,
    sortKey: 'priority',
    sortDirection: 'desc',
  });
});

test('deserializeViewFilters preserves explicit nulls for nullable fields only', () => {
  const decoded = deserializeViewFilters(JSON.stringify({
    listId: null,
    priority: null,
    showCompleted: true,
    horizonDays: null,
  }));

  assert.deepEqual(decoded, {
    listId: null,
    priority: null,
    showCompleted: true,
    horizonDays: null,
  });
});

test('deserializeViewFilters rejects payloads with unknown fields', () => {
  const decoded = deserializeViewFilters(JSON.stringify({
    search: 'alpha',
    dateRange: { start: '2026-04-24', end: '2026-04-25' },
  }));

  assert.deepEqual(decoded, {});
});

test('readSavedFilterEnum accepts only members from the allowed set', () => {
  assert.equal(
    readSavedFilterEnum('priority', ['default', 'priority', 'actionDate'] as const),
    'priority',
  );
  assert.equal(
    readSavedFilterEnum('bogus', ['default', 'priority', 'actionDate'] as const),
    undefined,
  );
  assert.equal(
    readSavedFilterEnum(7, ['default', 'priority', 'actionDate'] as const),
    undefined,
  );
});

test('serializeViewFilters keeps a compact payload for active fields only', () => {
  const raw = serializeViewFilters({
    search: 'alpha',
    filterListId: null,
    filterPriority: 2,
    selectedTags: new Set(['deep-work', 'focus']),
    showCompleted: false,
    showCancelled: false,
    groupBy: 'status',
    sortKey: 'priority',
    sortDirection: 'asc',
    horizonDays: 60,
  });

  assert.equal(raw, JSON.stringify({
    search: 'alpha',
    priority: 2,
    tags: ['deep-work', 'focus'],
    showCompleted: false,
    showCancelled: false,
    groupBy: 'status',
    sortKey: 'priority',
    sortDirection: 'asc',
    horizonDays: 60,
  }));
});

test('saved filter priority round-trips only canonical Priority values', () => {
  for (const priority of [1, 2, 3] as const) {
    const raw = serializeViewFilters({
      search: '',
      filterListId: null,
      filterPriority: priority,
      selectedTags: new Set(),
    });

    assert.deepEqual(deserializeViewFilters(raw), { priority });
  }

  for (const priority of [0, 4, 99, 1.5]) {
    assert.deepEqual(deserializeViewFilters(JSON.stringify({ priority })), {});
  }
});

test('readSavedFilterNumberEnum accepts only members from the allowed number set', () => {
  assert.equal(
    readSavedFilterNumberEnum(60, [7, 14, 30, 60, 90, null] as const),
    60,
  );
  assert.equal(
    readSavedFilterNumberEnum(45, [7, 14, 30, 60, 90, null] as const),
    undefined,
  );
  assert.equal(
    readSavedFilterNumberEnum('60', [7, 14, 30, 60, 90, null] as const),
    undefined,
  );
});
