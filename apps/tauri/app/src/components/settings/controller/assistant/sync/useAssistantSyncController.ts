import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';

import {
  createDefaultSyncBackendConfigs,
  getDefaultSyncBackendKind,
  getSyncBackendDescriptor,
  type SyncBackendConfigs,
} from '@/lib/syncBackend/model';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import type { SyncErrorEnvelope } from '@/lib/syncBackend/errorKind';
import { setPreference } from '@/lib/ipc/settings';
import { resetOutboxRetryCountsForTransportSwitch } from '@/lib/ipc/sync';
import {
  PREF_SYNC_BACKEND_CONFIGS,
  PREF_SYNC_BACKEND_KIND,
  PREF_SYNC_ENABLED,
} from '@/lib/preferences/keys';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { useVisibilityGatedInterval } from '@/lib/time/useVisibilityGatedInterval';
import {
  useAssistantSyncActions,
  type AssistantSyncPendingPreview,
  type AssistantSyncRunResult,
  type AssistantSyncStatus,
} from './actions';
import { useAssistantSyncAutosave } from './autosave';
import type { AssistantSyncAutosaveTimerHandle } from './autosave.runtime';
import { loadAssistantSyncBootstrap } from './bootstrap';
import { buildSyncStateBadge } from './presentation';
import type {
  AssistantSyncControllerState,
  SyncBackendSaveState,
  UseAssistantSyncControllerArgs,
} from './types';

export function useAssistantSyncController({
  syncBackendSupport,
  settingsMountedRef,
  formatSyncTimestamp,
  logAssistantSettingsError,
}: UseAssistantSyncControllerArgs): AssistantSyncControllerState {
  const { t, format } = useI18n();
  const [ready, setReady] = useState(false);
  const [syncStatus, setSyncStatus] = useState<AssistantSyncStatus | null>(null);
  const [syncStatusError, setSyncStatusError] = useState<string | null>(null);
  // keep the envelope of the most recent actionable
  // sync-run failure so the SyncMethodCard can render the same
  // remediation button the toast offered. Cleared on success.
  const [lastSyncErrorEnvelope, setLastSyncErrorEnvelope] =
    useState<SyncErrorEnvelope | null>(null);
  const [syncPendingPreview, setSyncPendingPreview] = useState<AssistantSyncPendingPreview>([]);
  const [draftSyncBackendKind, setDraftSyncBackendKind] = useState<SyncBackendKind | null>(null);
  const [syncBackendConfigs, setSyncBackendConfigs] = useState<SyncBackendConfigs>(
    createDefaultSyncBackendConfigs(),
  );
  const [syncEnabled, setSyncEnabled] = useState(false);
  const [defaultFilesystemBridgeRootPath, setDefaultFilesystemBridgeRootPath] = useState('');
  const [syncRunning, setSyncRunning] = useState(false);
  const [seedSyncRunning, setSeedSyncRunning] = useState(false);
  const [syncBackendSaveState, setSyncBackendSaveState] = useState<SyncBackendSaveState>('idle');
  const [lastSyncRunResult, setLastSyncRunResult] = useState<AssistantSyncRunResult | null>(null);
  const [syncLastRunAt, setSyncLastRunAt] = useState<string | null>(null);

  const syncBackendAutosaveResetTimerRef = useRef<AssistantSyncAutosaveTimerHandle | null>(null);
  const syncBackendAutosaveReadyRef = useRef(false);
  const syncBackendSaveSeqRef = useRef(0);
  const syncBackendDraftPendingRef = useRef<SyncBackendKind | null>(null);
  const assistantLoadSeqRef = useRef(0);
  const assistantRefreshRunningRef = useRef(false);
  const runtimeConfiguredSyncBackendKind = (syncStatus?.sync_backend_kind as SyncBackendKind | null) ?? null;
  const runtimeEffectiveSyncBackendKind = (syncStatus?.sync_backend_kind_effective as SyncBackendKind | null) ?? null;

  const {
    availableSyncBackendKinds,
    handleSeedFullSync,
    refreshSyncStatus,
    retrySaveSyncBackend,
    runSyncNow,
    saveSyncBackend,
    selectSyncBackend,
  } = useAssistantSyncActions({
    syncBackendSupport,
    logAssistantSettingsError,
    seedSyncRunning,
    setLastSyncRunResult,
    setSeedSyncRunning,
    setSyncBackendSaveState,
    setSyncLastRunAt,
    setSyncPendingPreview,
    setSyncRunning,
    setSyncStatus,
    setSyncStatusError,
    setLastSyncErrorEnvelope,
    setSyncBackendConfigs,
    setConfiguredSyncBackendKind: setDraftSyncBackendKind,
    settingsMountedRef,
    syncEnabled,
    syncRunning,
    syncBackendSaveState,
    syncBackendConfigs,
    configuredSyncBackendKind: draftSyncBackendKind,
    runtimeEffectiveSyncBackendKind,
    syncBackendDraftPendingRef,
    t,
    format,
  });

  useEffect(() => {
    let cancelled = false;
    const loadSeq = assistantLoadSeqRef.current + 1;
    assistantLoadSeqRef.current = loadSeq;
    const isCurrentLoad = () =>
      settingsMountedRef.current && !cancelled && assistantLoadSeqRef.current === loadSeq;

    async function load() {
      try {
        await loadAssistantSyncBootstrap({
          syncBackendSupport,
          isCurrentLoad,
          logAssistantSettingsError,
          refreshSyncStatus,
          setSyncBackendConfigs,
          setConfiguredSyncBackendKind: setDraftSyncBackendKind,
          setDefaultFilesystemBridgeRootPath,
          setSyncEnabled,
        });
      } finally {
        if (isCurrentLoad()) {
          setReady(true);
        }
      }
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, [
    syncBackendSupport,
    logAssistantSettingsError,
    refreshSyncStatus,
    settingsMountedRef,
  ]);

  // gate the 30s sync-status refresh on visibility so it
  // stops ticking when the main window is hidden (dock Cmd+H, menu-bar
  // popover collapse) while Settings was the last-rendered view.
  const syncStatusTick = useCallback(() => {
    if (!ready || assistantRefreshRunningRef.current) return;
    assistantRefreshRunningRef.current = true;
    void refreshSyncStatus()
      .finally(() => {
        assistantRefreshRunningRef.current = false;
      });
  }, [ready, refreshSyncStatus]);
  useVisibilityGatedInterval(syncStatusTick, 30_000);

  useAssistantSyncAutosave({
    ready,
    saveSyncBackend,
    setSyncBackendSaveState,
    settingsMountedRef,
    syncBackendAutosaveReadyRef,
    syncBackendAutosaveResetTimerRef,
    syncBackendSaveSeqRef,
    syncEnabled,
    syncBackendConfigs,
    configuredSyncBackendKind: draftSyncBackendKind,
  });

  const handleSyncEnabledToggle = useCallback((enabled: boolean) => {
    // Optimistic: set state immediately so the toggle doesn't flicker.
    setSyncEnabled(enabled);

    // Auto-select the first available backend when enabling, if none configured.
    let backendKindForSave = draftSyncBackendKind;
    if (enabled && backendKindForSave === null) {
      backendKindForSave = getDefaultSyncBackendKind(syncBackendSupport);
      if (backendKindForSave !== null) {
        syncBackendDraftPendingRef.current = backendKindForSave;
        setDraftSyncBackendKind(backendKindForSave);
      }
    }

    // Immediately persist to DB, bypassing the autosave debounce.
    // We call setPreference directly with the intended values to avoid
    // stale-closure issues with the saveSyncBackend callback.
    void (async () => {
      try {
        await Promise.all([
          setPreference(PREF_SYNC_ENABLED, enabled),
          setPreference(PREF_SYNC_BACKEND_KIND, backendKindForSave),
          setPreference(PREF_SYNC_BACKEND_CONFIGS, syncBackendConfigs),
        ]);
        if (syncBackendDraftPendingRef.current === backendKindForSave) {
          syncBackendDraftPendingRef.current = null;
        }
        await refreshSyncStatus();

        // Trigger an immediate sync cycle after enabling.
        if (enabled && settingsMountedRef.current) {
          void runSyncNow();
        }
      } catch (error: unknown) {
        reportClientError(
          'settings.syncToggle',
          'Immediate sync toggle save failed',
          error,
          undefined,
          'warn',
        );
      }
    })();
  }, [
    draftSyncBackendKind,
    refreshSyncStatus,
    runSyncNow,
    settingsMountedRef,
    syncBackendConfigs,
    syncBackendDraftPendingRef,
    syncBackendSupport,
  ]);

  // Wrap selectSyncBackend with immediate save to prevent flicker.
  const handleSelectSyncBackend = useCallback((backendKind: SyncBackendKind) => {
    const previousBackendKind = draftSyncBackendKind;
    selectSyncBackend(backendKind);
    // Immediately persist so the autosave/refresh race doesn't revert.
    void (async () => {
      try {
        await Promise.all([
          setPreference(PREF_SYNC_ENABLED, syncEnabled),
          setPreference(PREF_SYNC_BACKEND_KIND, backendKind),
          setPreference(PREF_SYNC_BACKEND_CONFIGS, syncBackendConfigs),
        ]);
        // when the user flips between transports, reset retry_count on every
        // unsynced outbox row. The previous transport's failures are
        // meaningless to the new one, and without this reset any row
        // already at MAX_RETRIES stays permanently quarantined.
        if (previousBackendKind !== null && previousBackendKind !== backendKind) {
          try {
            await resetOutboxRetryCountsForTransportSwitch();
          } catch (resetError) {
            reportClientError(
              'settings.syncBackendSelect.resetRetries',
              'Failed to reset outbox retry counts after transport switch',
              resetError,
              undefined,
              'warn',
            );
          }
        }
        syncBackendDraftPendingRef.current = null;
        await refreshSyncStatus();
      } catch (error: unknown) {
        reportClientError('settings.syncBackendSelect', 'Immediate backend save failed', error, undefined, 'warn');
      }
    })();
  }, [draftSyncBackendKind, selectSyncBackend, syncEnabled, syncBackendConfigs, refreshSyncStatus, syncBackendDraftPendingRef]);

  const syncStateBadge = useMemo(
    () => buildSyncStateBadge(syncStatus, t),
    [syncStatus, t],
  );
  const availableSyncBackendDescriptors = useMemo(
    () => availableSyncBackendKinds.map((backendKind) => getSyncBackendDescriptor(backendKind)),
    [availableSyncBackendKinds],
  );

  return {
    ready,
    sync: {
      draftSyncBackendKind,
      runtimeConfiguredSyncBackendKind,
      runtimeEffectiveSyncBackendKind,
      availableSyncBackendDescriptors,
      syncBackendConfigs,
      syncEnabled,
      defaultFilesystemBridgeRootPath,
      syncBackendSaveState,
      syncRunning,
      lastSyncRunResult,
      syncLastRunAt,
      syncStateBadge,
      syncStatus,
      syncPendingPreview,
      syncStatusError,
      lastSyncErrorEnvelope,
      formatSyncTimestamp,
      onRefreshSyncStatus: refreshSyncStatus,
      onSelectSyncBackend: handleSelectSyncBackend,
      onSyncEnabledChange: handleSyncEnabledToggle,
      onFilesystemBridgeRootPathChange: (value) => setSyncBackendConfigs((current) => ({
        ...current,
        filesystem_bridge: {
          rootPath: value,
        },
      })),
      onUseDefaultFilesystemBridgeRootPath: () => setSyncBackendConfigs((current) => ({
        ...current,
        filesystem_bridge: {
          rootPath: defaultFilesystemBridgeRootPath,
        },
      })),
      onRetrySaveSyncBackend: retrySaveSyncBackend,
      onRunSyncNow: runSyncNow,
      onSeedFullSync: handleSeedFullSync,
      seedSyncRunning,
    },
  };
}
