import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DEFAULT_MEMORY_LOCK_STATE,
  parseMemoryLockPreference,
  reconcileMemoryLockState,
} from '../../../app/src/lib/memoryLockPreference';

test('parseMemoryLockPreference fails closed for missing, malformed, and non-boolean values', () => {
  assert.equal(parseMemoryLockPreference(null), true);
  assert.equal(parseMemoryLockPreference('not json'), true);
  assert.equal(parseMemoryLockPreference('"false"'), true);
  assert.equal(parseMemoryLockPreference('123'), true);
});

test('reconcileMemoryLockState keeps an unlocked memory view unlocked while the preference remains enabled', () => {
  assert.deepEqual(
    reconcileMemoryLockState({ lockEnabled: true, isLocked: false }, 'true'),
    { lockEnabled: true, isLocked: false },
  );
});

test('reconcileMemoryLockState unlocks immediately when the preference is explicitly disabled', () => {
  assert.deepEqual(
    reconcileMemoryLockState(DEFAULT_MEMORY_LOCK_STATE, 'false'),
    { lockEnabled: false, isLocked: false },
  );
});

test('reconcileMemoryLockState re-locks when the preference transitions back to enabled', () => {
  assert.deepEqual(
    reconcileMemoryLockState({ lockEnabled: false, isLocked: false }, 'true'),
    DEFAULT_MEMORY_LOCK_STATE,
  );
});
