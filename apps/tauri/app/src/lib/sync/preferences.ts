import { reportClientError } from '../errors/errorLogging';
import { getDefaultFilesystemBridgeRootPath } from '../ipc/sync';
import { getPreference, setPreference } from '../ipc/settings';
import {
  PREF_SYNC_BACKEND_CONFIGS,
  PREF_SYNC_BACKEND_KIND,
  PREF_SYNC_ENABLED,
} from '../preferences/keys';
import {
  buildSyncBackendConfig,
  type SyncBackendSettings,
  type SyncBackendConfig,
  type SyncBackendSupportContext,
} from '../syncBackend/model';
import { resolveStoredSyncBackendSettings } from '../syncBackend/preferences';

interface ResolvedBackgroundSyncPreferences {
  settings: SyncBackendSettings;
  activeBackend: SyncBackendConfig | null;
  shouldPersistNormalized: boolean;
}

interface BackgroundSyncNormalizationState {
  normalizedSettings: boolean;
}

export async function loadResolvedBackgroundSyncPreferences(options: {
  syncBackendSupport: SyncBackendSupportContext;
}): Promise<ResolvedBackgroundSyncPreferences> {
  const [enabledRaw, backendKindRaw, backendConfigsRaw] = await Promise.all([
    getPreference(PREF_SYNC_ENABLED),
    getPreference(PREF_SYNC_BACKEND_KIND),
    getPreference(PREF_SYNC_BACKEND_CONFIGS),
  ]);
  const defaultFilesystemBridgeRootPath = await getDefaultFilesystemBridgeRootPath().catch(() => null);
  const resolvedSettings = resolveStoredSyncBackendSettings({
    enabledRaw,
    backendKindRaw,
    backendConfigsRaw,
    defaultFilesystemBridgeRootPath,
    syncBackendSupport: options.syncBackendSupport,
  });

  return {
    settings: resolvedSettings.settings,
    activeBackend: buildSyncBackendConfig({
      backendKind: resolvedSettings.settings.effectiveBackendKind,
      backendConfigs: resolvedSettings.settings.backendConfigs,
    }),
    shouldPersistNormalized: resolvedSettings.shouldPersistNormalized,
  };
}

export function scheduleResolvedBackgroundSyncNormalization(options: {
  settings: SyncBackendSettings;
  normalizationState: BackgroundSyncNormalizationState;
  shouldPersistNormalized: boolean;
}): void {
  const { settings, normalizationState, shouldPersistNormalized } = options;

  if (!shouldPersistNormalized || normalizationState.normalizedSettings) {
    return;
  }

  void Promise.all([
    setPreference(PREF_SYNC_BACKEND_CONFIGS, settings.backendConfigs),
  ])
    .then(() => {
      normalizationState.normalizedSettings = true;
    })
    .catch((error) => {
      reportClientError(
        'sync.default_backend_settings',
        'Persist normalized sync backend settings failed',
        error,
        settings.backendConfigs.filesystem_bridge.rootPath,
        'warn',
      );
    });
}
