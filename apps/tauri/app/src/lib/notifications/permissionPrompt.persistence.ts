import type { DeviceStateKey } from '../preferences/keys';
import type { NotificationPermissionPromptCancellationProbe } from './permissionPrompt.runtime';

export interface NotificationPermissionPromptDeviceStateStore {
  getDeviceState: (key: DeviceStateKey) => Promise<string | null>;
  setDeviceState: (key: DeviceStateKey, value: unknown) => Promise<void>;
}

const writeQueues = new Map<string, Promise<void>>();

export async function getNotificationPermissionPromptDeviceState(
  store: NotificationPermissionPromptDeviceStateStore,
  key: DeviceStateKey,
): Promise<string | null> {
  await (writeQueues.get(key) ?? Promise.resolve()).catch(() => {});
  return store.getDeviceState(key);
}

export async function setNotificationPermissionPromptDeviceState(
  store: NotificationPermissionPromptDeviceStateStore,
  key: DeviceStateKey,
  value: boolean,
  isCancelled: NotificationPermissionPromptCancellationProbe,
): Promise<void> {
  const previousWrite = writeQueues.get(key) ?? Promise.resolve();
  const queuedWrite = previousWrite
    .catch(() => {})
    .then(() => setNotificationPermissionPromptDeviceStateNow(
      store,
      key,
      value,
      isCancelled,
    ));

  writeQueues.set(key, queuedWrite);

  try {
    await queuedWrite;
  } finally {
    if (writeQueues.get(key) === queuedWrite) {
      writeQueues.delete(key);
    }
  }
}

async function setNotificationPermissionPromptDeviceStateNow(
  store: NotificationPermissionPromptDeviceStateStore,
  key: DeviceStateKey,
  value: boolean,
  isCancelled: NotificationPermissionPromptCancellationProbe,
): Promise<void> {
  if (isCancelled()) return;

  const previousRawValue = await store.getDeviceState(key);
  if (isCancelled()) return;

  await store.setDeviceState(key, value);
  if (!isCancelled()) return;

  await restoreNotificationPermissionPromptDeviceState(store, key, previousRawValue);
}

async function restoreNotificationPermissionPromptDeviceState(
  store: NotificationPermissionPromptDeviceStateStore,
  key: DeviceStateKey,
  previousRawValue: string | null,
): Promise<void> {
  if (previousRawValue === null) {
    await store.setDeviceState(key, null);
    return;
  }

  await store.setDeviceState(key, parsePersistedBoolean(previousRawValue));
}

/**
 * The persisted device-state value is always written via
 * `setDeviceState(key, boolean)` (see
 * {@link setNotificationPermissionPromptDeviceState}), so the only
 * legal raw forms are the JSON encodings of `true` / `false`.
 *
 * Branching on string equality is exhaustive for the boolean
 * encoding and never throws; an unrecognized value (corrupted
 * store, foreign writer) falls back to `null` so the writer-side
 * `setDeviceState` clears the slot — the same shape an empty slot
 * would have produced. A plain `JSON.parse` would throw
 * synchronously and escape through the cancellation-restore path
 * as an unhandled promise rejection.
 */
function parsePersistedBoolean(raw: string): boolean | null {
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  return null;
}
