import { useCallback } from 'react';

import { seedFullSync } from '@/lib/ipc/sync';
import { toast } from '@/lib/notifications/toast';
import type { UseAssistantSyncActionsArgs } from './types';

interface UseAssistantSyncSeedActionArgs {
  logAssistantSettingsError: UseAssistantSyncActionsArgs['logAssistantSettingsError'];
  refreshSyncStatus: () => Promise<void>;
  runSyncNow: () => Promise<void>;
  seedSyncRunning: UseAssistantSyncActionsArgs['seedSyncRunning'];
  setSeedSyncRunning: UseAssistantSyncActionsArgs['setSeedSyncRunning'];
  settingsMountedRef: UseAssistantSyncActionsArgs['settingsMountedRef'];
  t: UseAssistantSyncActionsArgs['t'];
  format: UseAssistantSyncActionsArgs['format'];
}

export function useAssistantSyncSeedAction({
  logAssistantSettingsError,
  refreshSyncStatus,
  runSyncNow,
  seedSyncRunning,
  setSeedSyncRunning,
  settingsMountedRef,
  t,
  format,
}: UseAssistantSyncSeedActionArgs) {
  const handleSeedFullSync = useCallback(async () => {
    if (seedSyncRunning) return;

    setSeedSyncRunning(true);
    toast.info(t('settings.seedFullSyncStarted'));

    // Fire-and-forget: seed then trigger sync, all non-blocking.
    seedFullSync().then((result) => {
      if (!settingsMountedRef.current) return;
      toast.success(
        format('settings.seedFullSyncSuccess', {
          tasks: String(result.tasks_enqueued),
          lists: String(result.lists_enqueued),
        }),
      );
      setSeedSyncRunning(false);
      void refreshSyncStatus();
      // Trigger sync to push the seeded events (also non-blocking)
      void runSyncNow();
    }).catch((error: unknown) => {
      logAssistantSettingsError('frontend.settings.sync.seed', 'Seed full sync failed', error);
      if (settingsMountedRef.current) {
        setSeedSyncRunning(false);
      }
      // route via errorWithDetail so disk-full sentinels and
      // Rust-internal leakage get redacted, while genuine backend messages
      // ("sync not configured") still reach the user.
      toast.errorWithDetail(error, t('settings.seedFullSyncFailed'));
    });
  }, [
    logAssistantSettingsError,
    refreshSyncStatus,
    runSyncNow,
    seedSyncRunning,
    setSeedSyncRunning,
    settingsMountedRef,
    t,
    format,
  ]);

  return { handleSeedFullSync };
}
