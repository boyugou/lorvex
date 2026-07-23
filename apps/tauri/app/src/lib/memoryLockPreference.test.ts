import { describe, expect, it } from 'vitest';

import {
  DEFAULT_MEMORY_LOCK_STATE,
  parseMemoryLockPreference,
  reconcileMemoryLockEnabledState,
  reconcileMemoryLockState,
} from './memoryLockPreference';

describe('memory lock preference parsing', () => {
  it('defaults to enabled for absent or invalid stored values', () => {
    expect(parseMemoryLockPreference(null)).toBe(true);
    expect(parseMemoryLockPreference('not-json')).toBe(true);
    expect(parseMemoryLockPreference('"wrong-type"')).toBe(true);
  });

  it('parses explicit boolean stored values', () => {
    expect(parseMemoryLockPreference('true')).toBe(true);
    expect(parseMemoryLockPreference('false')).toBe(false);
  });

  it('reconciles parsed enabled state without requiring callers to keep raw strings', () => {
    expect(reconcileMemoryLockEnabledState(DEFAULT_MEMORY_LOCK_STATE, false))
      .toEqual({ lockEnabled: false, isLocked: false });
    expect(reconcileMemoryLockState(DEFAULT_MEMORY_LOCK_STATE, 'false'))
      .toEqual({ lockEnabled: false, isLocked: false });
    expect(reconcileMemoryLockEnabledState({ lockEnabled: false, isLocked: false }, true))
      .toEqual(DEFAULT_MEMORY_LOCK_STATE);
  });
});
