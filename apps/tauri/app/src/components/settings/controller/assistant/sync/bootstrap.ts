import { getPreference, setPreference } from '@/lib/ipc/settings';
import { getDefaultFilesystemBridgeRootPath } from '@/lib/ipc/sync';
import {
  PREF_SYNC_BACKEND_CONFIGS,
  PREF_SYNC_BACKEND_KIND,
  PREF_SYNC_ENABLED,
} from '@/lib/preferences/keys';
import { resolveStoredSyncBackendSettings } from '@/lib/syncBackend/preferences';
import type {
  SyncBackendConfigs,
  SyncBackendSupportContext,
} from '@/lib/syncBackend/model';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';

interface LoadAssistantSyncBootstrapArgs {
  syncBackendSupport: SyncBackendSupportContext;
  isCurrentLoad: () => boolean;
  logAssistantSettingsError: (source: string, message: string, error: unknown) => void;
  refreshSyncStatus: () => Promise<void>;
  setSyncBackendConfigs: (value: SyncBackendConfigs) => void;
  setConfiguredSyncBackendKind: (value: SyncBackendKind | null) => void;
  setDefaultFilesystemBridgeRootPath: (value: string) => void;
  setSyncEnabled: (value: boolean) => void;
}

export async function loadAssistantSyncBootstrap({
  syncBackendSupport,
  isCurrentLoad,
  logAssistantSettingsError,
  refreshSyncStatus,
  setSyncBackendConfigs,
  setConfiguredSyncBackendKind,
  setDefaultFilesystemBridgeRootPath,
  setSyncEnabled,
}: LoadAssistantSyncBootstrapArgs): Promise<void> {
  const [enabledRaw, backendKindRaw, backendConfigsRaw] = await Promise.all([
    getPreference(PREF_SYNC_ENABLED),
    getPreference(PREF_SYNC_BACKEND_KIND),
    getPreference(PREF_SYNC_BACKEND_CONFIGS),
  ]);
  if (!isCurrentLoad()) return;

  try {
    const defaultFilesystemBridgeRootPath = await getDefaultFilesystemBridgeRootPath();
    if (!isCurrentLoad()) return;
    const resolvedSettings = resolveStoredSyncBackendSettings({
      enabledRaw,
      backendKindRaw,
      backendConfigsRaw,
      defaultFilesystemBridgeRootPath,
      syncBackendSupport,
    });

    setSyncEnabled(resolvedSettings.settings.enabled);
    setConfiguredSyncBackendKind(resolvedSettings.settings.configuredBackendKind);
    setSyncBackendConfigs(resolvedSettings.settings.backendConfigs);
    setDefaultFilesystemBridgeRootPath(defaultFilesystemBridgeRootPath?.trim() ?? '');

    if (resolvedSettings.shouldPersistNormalized) {
      void setPreference(PREF_SYNC_BACKEND_CONFIGS, resolvedSettings.settings.backendConfigs).catch((error) => {
        logAssistantSettingsError(
          'frontend.settings.sync.persist_backend_settings',
          'Persist normalized sync backend settings failed',
          error,
        );
      });
    }
  } catch {
    if (!isCurrentLoad()) return;
    const resolvedSettings = resolveStoredSyncBackendSettings({
      enabledRaw,
      backendKindRaw,
      backendConfigsRaw,
      defaultFilesystemBridgeRootPath: null,
      syncBackendSupport,
    });
    setSyncEnabled(resolvedSettings.settings.enabled);
    setConfiguredSyncBackendKind(resolvedSettings.settings.configuredBackendKind);
    setSyncBackendConfigs(resolvedSettings.settings.backendConfigs);
    setDefaultFilesystemBridgeRootPath('');
  }

  await refreshSyncStatus();
}
