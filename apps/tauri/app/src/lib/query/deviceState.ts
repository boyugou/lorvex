import type { QueryClient } from '@tanstack/react-query';

import { setDeviceState } from '@/lib/ipc/settings';
import type { DeviceStateKey } from '../preferences/keys';
import type { DeviceStateValueOf } from '../preferences/values';
import { QUERY_KEYS } from './queryKeyFactory';

type DeviceStateWriter<K extends DeviceStateKey> = (
  key: K,
  value: DeviceStateValueOf<K>,
) => Promise<void>;

export function serializeDeviceStateQueryValue(value: unknown): string | null {
  if (value === null) return null;
  return JSON.stringify(value);
}

export function setDeviceStateQueryData<K extends DeviceStateKey>(
  queryClient: QueryClient,
  key: K,
  value: DeviceStateValueOf<K>,
): void {
  queryClient.setQueryData(
    QUERY_KEYS.deviceState(key),
    serializeDeviceStateQueryValue(value),
  );
}

export async function writeDeviceStateWithQueryUpdate<K extends DeviceStateKey>({
  key,
  queryClient,
  value,
  writeDeviceState = setDeviceState,
}: {
  key: K;
  queryClient: QueryClient;
  value: DeviceStateValueOf<K>;
  writeDeviceState?: DeviceStateWriter<K>;
}): Promise<void> {
  await writeDeviceState(key, value);
  setDeviceStateQueryData(queryClient, key, value);
}
