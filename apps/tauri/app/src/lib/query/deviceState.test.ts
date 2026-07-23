import { describe, expect, it, vi } from 'vitest';
import { QueryClient } from '@tanstack/react-query';

import {
  DEV_FOCUS_SESSION_TRIED,
  DEV_ONBOARDING_PREVIOUSLY_DONE,
} from '../preferences/keys';
import { QUERY_KEYS } from './queryKeys';
import {
  serializeDeviceStateQueryValue,
  setDeviceStateQueryData,
  writeDeviceStateWithQueryUpdate,
} from './deviceState';

describe('device state query updates', () => {
  it('serializes device-state values into the same raw shape getDeviceState returns', () => {
    expect(serializeDeviceStateQueryValue(true)).toBe('true');
    expect(serializeDeviceStateQueryValue(['mcp', 'focus'])).toBe('["mcp","focus"]');
    expect(serializeDeviceStateQueryValue(null)).toBeNull();
  });

  it('updates the scoped device-state query after a successful write', async () => {
    const queryClient = new QueryClient();
    const writeDeviceState = vi.fn(async () => undefined);

    await writeDeviceStateWithQueryUpdate({
      key: DEV_FOCUS_SESSION_TRIED,
      queryClient,
      value: true,
      writeDeviceState,
    });

    expect(writeDeviceState).toHaveBeenCalledWith(DEV_FOCUS_SESSION_TRIED, true);
    expect(queryClient.getQueryData(QUERY_KEYS.deviceState(DEV_FOCUS_SESSION_TRIED))).toBe('true');
  });

  it('does not update query data when the write fails', async () => {
    const queryClient = new QueryClient();
    const writeDeviceState = vi.fn(async () => {
      throw new Error('write failed');
    });

    await expect(writeDeviceStateWithQueryUpdate({
      key: DEV_ONBOARDING_PREVIOUSLY_DONE,
      queryClient,
      value: ['mcp'],
      writeDeviceState,
    })).rejects.toThrow('write failed');

    expect(
      queryClient.getQueryData(QUERY_KEYS.deviceState(DEV_ONBOARDING_PREVIOUSLY_DONE)),
    ).toBeUndefined();
  });

  it('can update cache directly when another layer owns the write', () => {
    const queryClient = new QueryClient();

    setDeviceStateQueryData(queryClient, DEV_ONBOARDING_PREVIOUSLY_DONE, ['sync']);

    expect(
      queryClient.getQueryData(QUERY_KEYS.deviceState(DEV_ONBOARDING_PREVIOUSLY_DONE)),
    ).toBe('["sync"]');
  });
});
