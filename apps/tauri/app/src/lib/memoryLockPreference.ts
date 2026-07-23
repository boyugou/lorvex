import { parseBooleanPreference } from './preferences/parser';

interface MemoryLockState {
  lockEnabled: boolean;
  isLocked: boolean;
}

export const DEFAULT_MEMORY_LOCK_STATE: MemoryLockState = {
  lockEnabled: true,
  isLocked: true,
};

export function parseMemoryLockPreference(raw: string | null): boolean {
  return parseBooleanPreference(raw, true);
}

export function reconcileMemoryLockState(
  current: MemoryLockState,
  raw: string | null,
): MemoryLockState {
  return reconcileMemoryLockEnabledState(current, parseMemoryLockPreference(raw));
}

export function reconcileMemoryLockEnabledState(
  current: MemoryLockState,
  enabled: boolean,
): MemoryLockState {
  if (!enabled) {
    return {
      lockEnabled: false,
      isLocked: false,
    };
  }

  if (!current.lockEnabled) {
    return DEFAULT_MEMORY_LOCK_STATE;
  }

  return {
    lockEnabled: true,
    isLocked: current.isLocked,
  };
}
