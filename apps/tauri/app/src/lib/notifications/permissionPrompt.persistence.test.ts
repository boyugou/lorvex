import { describe, expect, it, vi } from 'vitest';

import { DEV_NOTIFICATION_PERMISSION_PROMPTED } from '../preferences/keys';
import {
  getNotificationPermissionPromptDeviceState,
  setNotificationPermissionPromptDeviceState,
  type NotificationPermissionPromptDeviceStateStore,
} from './permissionPrompt.persistence';

/** Use a real registry key so the typed `DeviceStateKey` parameters
 *  on the persistence helpers accept the value at compile time. The
 *  helpers themselves are key-agnostic — any registry key works. */
const TEST_KEY = DEV_NOTIFICATION_PERMISSION_PROMPTED;

/**
 * Vitest harness lives in Node — no DOM, no React. The persistence
 * layer is a pure function over a `{ getDeviceState, setDeviceState }`
 * store, so a Map-backed in-memory shim is sufficient.
 */
function createStore(initial: Record<string, string | null> = {}): {
  store: NotificationPermissionPromptDeviceStateStore;
  data: Map<string, unknown>;
  setRaw: (key: string, value: unknown) => void;
} {
  // The persistence layer reads via `getDeviceState` (returns the
  // serialized string) but writes typed values via `setDeviceState`.
  // Track the typed write target separately from the seeded raw
  // string so the read path returns the canonical "true"/"false"/
  // corrupted blob the cancellation-restore branch will see.
  const data = new Map<string, unknown>();
  const raw = new Map<string, string | null>(Object.entries(initial));
  return {
    data,
    setRaw: (key, value) => {
      raw.set(key, value as string | null);
    },
    store: {
      getDeviceState: async (key) => {
        return raw.get(key) ?? null;
      },
      setDeviceState: async (key, value) => {
        data.set(key, value);
      },
    },
  };
}

/**
 * Cancellation probe that returns `true` only AFTER the writer has
 * had a chance to call it `firesAfter` times. The pre-fix
 * `setNotificationPermissionPromptDeviceStateNow` calls the probe
 * three times (start, after read, after write). Returning `true` on
 * the 3rd call simulates "the caller cancelled while the write was
 * in-flight" without racing real timers.
 */
function probeAfter(firesAfter: number): () => boolean {
  let calls = 0;
  return () => {
    calls += 1;
    return calls > firesAfter;
  };
}

describe('permissionPrompt.persistence — restore path', () => {
  it('restores `true` from the canonical "true" string without throwing', async () => {
    const { store, data } = createStore({ [TEST_KEY]: 'true' });
    await setNotificationPermissionPromptDeviceState(store, TEST_KEY, false, probeAfter(2));
    // After cancellation the store should be restored to the
    // pre-write boolean (true), not the JSON string "true".
    expect(data.get(TEST_KEY)).toBe(true);
  });

  it('restores `false` from the canonical "false" string without throwing', async () => {
    const { store, data } = createStore({ [TEST_KEY]: 'false' });
    await setNotificationPermissionPromptDeviceState(store, TEST_KEY, true, probeAfter(2));
    expect(data.get(TEST_KEY)).toBe(false);
  });

  it('falls back to null on a corrupted previous value instead of throwing', async () => {
    // Pre-fix, JSON.parse on `{not-json` would synchronously throw
    // and escape as an unhandled promise rejection.
    const { store, data } = createStore({ [TEST_KEY]: '{not-json' });
    await expect(
      setNotificationPermissionPromptDeviceState(store, TEST_KEY, true, probeAfter(2)),
    ).resolves.toBeUndefined();
    expect(data.get(TEST_KEY)).toBeNull();
  });

  it('falls back to null on an unrecognized boolean encoding', async () => {
    const { store, data } = createStore({ [TEST_KEY]: 'TRUE' /* wrong case */ });
    await setNotificationPermissionPromptDeviceState(store, TEST_KEY, true, probeAfter(2));
    expect(data.get(TEST_KEY)).toBeNull();
  });

  it('restores to null when the previous value was null (slot empty)', async () => {
    const { store, data } = createStore({});
    const setSpy = vi.spyOn(store, 'setDeviceState');
    await setNotificationPermissionPromptDeviceState(store, TEST_KEY, true, probeAfter(2));
    // Two writes: the cancelled write itself, and the restore-to-null.
    expect(setSpy).toHaveBeenCalledTimes(2);
    expect(data.get(TEST_KEY)).toBeNull();
  });

  it('passes the queued read through getDeviceState helper untouched', async () => {
    const { store } = createStore({ [TEST_KEY]: 'true' });
    const v = await getNotificationPermissionPromptDeviceState(store, TEST_KEY);
    expect(v).toBe('true');
  });
});
