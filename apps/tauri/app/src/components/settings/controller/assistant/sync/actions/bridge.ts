import { useCallback } from 'react';
import { setPreference } from '@/lib/ipc/settings';
import {
  PREF_SYNC_BACKEND_CONFIGS,
  PREF_SYNC_BACKEND_KIND,
  PREF_SYNC_ENABLED,
} from '@/lib/preferences/keys';
import type { SyncBackendConfigs } from '@/lib/syncBackend/model';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import { toast } from '@/lib/notifications/toast';
import type { UseAssistantSyncActionsArgs } from './types';

interface UseAssistantSyncBackendActionsArgs {
  configuredSyncBackendKind: SyncBackendKind | null;
  logAssistantSettingsError: UseAssistantSyncActionsArgs['logAssistantSettingsError'];
  refreshSyncStatus: () => Promise<void>;
  setSyncBackendSaveState: UseAssistantSyncActionsArgs['setSyncBackendSaveState'];
  settingsMountedRef: UseAssistantSyncActionsArgs['settingsMountedRef'];
  syncEnabled: UseAssistantSyncActionsArgs['syncEnabled'];
  syncBackendConfigs: SyncBackendConfigs;
  syncBackendDraftPendingRef: UseAssistantSyncActionsArgs['syncBackendDraftPendingRef'];
  t: UseAssistantSyncActionsArgs['t'];
}

export function useAssistantSyncBackendActions({
  configuredSyncBackendKind,
  logAssistantSettingsError,
  refreshSyncStatus,
  setSyncBackendSaveState,
  settingsMountedRef,
  syncEnabled,
  syncBackendConfigs,
  syncBackendDraftPendingRef,
  t,
}: UseAssistantSyncBackendActionsArgs) {
  const saveSyncBackend = useCallback(async (notify: boolean) => {
    try {
      await Promise.all([
        setPreference(PREF_SYNC_ENABLED, syncEnabled),
        setPreference(PREF_SYNC_BACKEND_KIND, configuredSyncBackendKind),
        setPreference(PREF_SYNC_BACKEND_CONFIGS, syncBackendConfigs),
      ]);
      if (syncBackendDraftPendingRef.current === configuredSyncBackendKind) {
        syncBackendDraftPendingRef.current = null;
      }
      if (notify) {
        toast.success(t('settings.syncSettingsSaved'));
      }
      await refreshSyncStatus();
    } catch (error) {
      logAssistantSettingsError('frontend.settings.sync.save', 'Save sync backend settings failed', error);
      if (notify) {
        // the sync-settings save fires three `setPreference`
        // IPC calls — a failure (disk-full, preferences DB lock, invalid
        // JSON shape) should surface the specific reason so the user can
        // recover rather than silently retry.
        toast.errorWithDetail(error, t('settings.syncSettingsSaveFailed'));
      }
      throw error;
    }
  }, [
    configuredSyncBackendKind,
    logAssistantSettingsError,
    refreshSyncStatus,
    syncEnabled,
    syncBackendConfigs,
    syncBackendDraftPendingRef,
    t,
  ]);

  const retrySaveSyncBackend = useCallback(() => {
    setSyncBackendSaveState('saving');
    void saveSyncBackend(true)
      .then(() => {
        if (settingsMountedRef.current) {
          setSyncBackendSaveState('saved');
        }
      })
      .catch((error: unknown) => {
        logAssistantSettingsError('retrySaveSyncBackend', 'Retry sync backend save failed', error);
        if (settingsMountedRef.current) {
          setSyncBackendSaveState('error');
        }
      });
  }, [logAssistantSettingsError, saveSyncBackend, setSyncBackendSaveState, settingsMountedRef]);

  return {
    retrySaveSyncBackend,
    saveSyncBackend,
  };
}
