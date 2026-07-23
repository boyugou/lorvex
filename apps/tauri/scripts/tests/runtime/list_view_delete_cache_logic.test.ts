import assert from 'node:assert/strict';
import test from 'node:test';

import { shouldKeepCachedListEntry } from '../../../app/src/components/list-view/deleteCache';

test('list delete cache filtering removes only entries with an own matching id', () => {
  assert.equal(shouldKeepCachedListEntry({ id: 'list-a' }, 'list-a'), false);
  assert.equal(
    shouldKeepCachedListEntry(Object.defineProperty({}, 'id', { value: 'list-a' }), 'list-a'),
    false,
  );
  assert.equal(shouldKeepCachedListEntry({ id: 'list-b' }, 'list-a'), true);
  assert.equal(shouldKeepCachedListEntry(Object.create({ id: 'list-a' }), 'list-a'), true);
  assert.equal(shouldKeepCachedListEntry({ id: 42 }, 'list-a'), true);
  assert.equal(shouldKeepCachedListEntry(null, 'list-a'), true);
  assert.equal(shouldKeepCachedListEntry(['list-a'], 'list-a'), true);
});

test('list delete cache filtering ignores own id accessors without invoking getters', () => {
  const entry = Object.defineProperty({}, 'id', {
    get() {
      throw new Error('id getter should not run');
    },
  });

  assert.equal(shouldKeepCachedListEntry(entry, 'list-a'), true);
});
