import { useCallback, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';

import { clearNativeCalendarEvents } from '@/lib/ipc/calendar';
import { getDeviceState, setDeviceState } from '@/lib/ipc/settings';
import { useI18n } from '@/lib/i18n';
import { getNativeCalendarRuntimeConfig, type NativeCalendarSyncSummary } from '@/lib/nativeCalendarRuntime';
import { QK, QUERY_KEYS, invalidateDeviceStateQueries } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { toast } from '@/lib/notifications/toast';
import { useRuntimeProfile } from '@/lib/useRuntimeProfile';
import {
  clearNativeCalendarPanelProviderEvents,
  syncNativeCalendarPanelNow,
} from './useNativeCalendarPanelController.logic';

export function useNativeCalendarPanelController() {
  const runtimeProfile = useRuntimeProfile();
  const config = getNativeCalendarRuntimeConfig(runtimeProfile);
  const { t, format } = useI18n();
  const queryClient = useQueryClient();
  const [syncing, setSyncing] = useState(false);
  const [lastResult, setLastResult] = useState<NativeCalendarSyncSummary | null>(null);

  const deviceStateKey = config?.deviceStateKey ?? null;

  const { data: raw } = useQuery({
    queryKey: deviceStateKey === null
      ? QUERY_KEYS.head(QK.deviceState)
      : QUERY_KEYS.deviceState(deviceStateKey),
    queryFn: ({ signal }) => deviceStateKey
      ? getDeviceState(deviceStateKey, signal)
      : Promise.resolve(null),
    staleTime: STALE_DEFAULT,
    enabled: deviceStateKey !== null,
  });

  const enabled = raw === 'true';

  const persistEnabled = useCallback(async (value: boolean) => {
    if (!deviceStateKey) return;
    await setDeviceState(deviceStateKey, value);
    invalidateDeviceStateQueries(queryClient, deviceStateKey);
  }, [deviceStateKey, queryClient]);

  const handleSync = useCallback(async () => {
    if (!config) return;

    setSyncing(true);
    try {
      await syncNativeCalendarPanelNow({
        queryClient,
        setLastResult,
        syncNow: config.syncNow,
        t,
        format,
        toast,
      });
    } finally {
      setSyncing(false);
    }
  }, [config, format, queryClient, t]);

  const handleToggle = useCallback(async () => {
    if (!config) return;

    const next = !enabled;
    await persistEnabled(next);
    if (next) {
      void handleSync();
      return;
    }

    await clearNativeCalendarPanelProviderEvents({
      clearNativeCalendarEvents,
      clearProviderKind: config.clearProviderKind,
      queryClient,
      t,
      format,
      toast,
    });
  }, [config, enabled, format, handleSync, persistEnabled, queryClient, t]);

  return {
    config,
    enabled,
    handleSync,
    handleToggle,
    lastResult,
    syncing,
  };
}
