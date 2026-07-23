import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  deserializeViewFilters,
  readSavedFilterEnum,
  readSavedFilterNumberEnum,
  serializeViewFilters,
} from '../../../app/src/lib/tasks/savedFilterShape';

test('saved filter serializer omits empty values, preserves explicit booleans, and sorts tags', () => {
  const payload = serializeViewFilters({
    search: '   ',
    filterListId: null,
    filterPriority: null,
    selectedTags: new Set(['urgent', 'blocked']),
    showCompleted: false,
    showCancelled: true,
  });

  assert.equal(payload, '{"tags":["blocked","urgent"],"showCompleted":false,"showCancelled":true}');
});

test('saved filter shape round-trips supported filter fields through the real parser', () => {
  const decoded = deserializeViewFilters(serializeViewFilters({
    search: 'standup',
    filterListId: 'list-123',
    filterPriority: 1,
    selectedTags: new Set(['work', 'urgent']),
    showCompleted: true,
    showCancelled: false,
    groupBy: 'priority',
    sortKey: 'dueDate',
    sortDirection: 'desc',
    horizonDays: 14,
  }));

  assert.deepEqual(decoded, {
    search: 'standup',
    listId: 'list-123',
    priority: 1,
    tags: ['urgent', 'work'],
    showCompleted: true,
    showCancelled: false,
    groupBy: 'priority',
    sortKey: 'dueDate',
    sortDirection: 'desc',
    horizonDays: 14,
  });
});

test('saved filter deserializer fails closed for malformed, non-object, and unknown-field payloads', () => {
  assert.deepEqual(deserializeViewFilters('not-json{'), {});
  assert.deepEqual(deserializeViewFilters('null'), {});
  assert.deepEqual(deserializeViewFilters('[1,2,3]'), {});
  assert.deepEqual(deserializeViewFilters('"string"'), {});
  assert.deepEqual(deserializeViewFilters('{"search":"ok","unexpected":true}'), {});
});

test('saved filter enum helpers accept only explicit allowlist values', () => {
  assert.equal(readSavedFilterEnum('desc', ['asc', 'desc']), 'desc');
  assert.equal(readSavedFilterEnum('random', ['asc', 'desc']), undefined);
  assert.equal(readSavedFilterNumberEnum(7, [7, 14, null]), 7);
  assert.equal(readSavedFilterNumberEnum(null, [7, 14, null]), null);
  assert.equal(readSavedFilterNumberEnum(30, [7, 14, null]), undefined);
});

test('saved filter parser delegates JSON parsing to the shared helper', () => {
  const source = readFileSync('app/src/lib/tasks/savedFilterShape.ts', 'utf8');
  assert.match(source, /import \{ tryParseJson \} from '\.\.\/security\/jsonParse';/);
  assert.doesNotMatch(source, /JSON\.parse\(/);
});
