import { useAssistantSyncBackendActions } from './actions/bridge';
import { useAssistantSyncRunNowAction } from './actions/run';
import { useAssistantSyncSeedAction } from './actions/seed';
import { useAssistantSyncStatusActions } from './actions/status';
import { useAssistantSyncBackendSelection } from './actions/transport';
import type { UseAssistantSyncActionsArgs } from './actions/types';

export type {
  AssistantSyncPendingPreview,
  AssistantSyncRunResult,
  AssistantSyncStatus,
} from './actions/types';

export function useAssistantSyncActions(args: UseAssistantSyncActionsArgs) {
  const { refreshSyncStatus } = useAssistantSyncStatusActions({
    setSyncLastRunAt: args.setSyncLastRunAt,
    setSyncPendingPreview: args.setSyncPendingPreview,
    setSyncStatus: args.setSyncStatus,
    setSyncStatusError: args.setSyncStatusError,
    setConfiguredSyncBackendKind: args.setConfiguredSyncBackendKind,
    settingsMountedRef: args.settingsMountedRef,
    syncBackendDraftPendingRef: args.syncBackendDraftPendingRef,
  });
  const {
    availableSyncBackendKinds,
    selectSyncBackend,
  } = useAssistantSyncBackendSelection({
    syncBackendSupport: args.syncBackendSupport,
    setConfiguredSyncBackendKind: args.setConfiguredSyncBackendKind,
    syncBackendDraftPendingRef: args.syncBackendDraftPendingRef,
  });
  const {
    retrySaveSyncBackend,
    saveSyncBackend,
  } = useAssistantSyncBackendActions({
    configuredSyncBackendKind: args.configuredSyncBackendKind,
    logAssistantSettingsError: args.logAssistantSettingsError,
    refreshSyncStatus,
    setSyncBackendSaveState: args.setSyncBackendSaveState,
    settingsMountedRef: args.settingsMountedRef,
    syncEnabled: args.syncEnabled,
    syncBackendConfigs: args.syncBackendConfigs,
    syncBackendDraftPendingRef: args.syncBackendDraftPendingRef,
    t: args.t,
  });
  const { runSyncNow } = useAssistantSyncRunNowAction({
    logAssistantSettingsError: args.logAssistantSettingsError,
    refreshSyncStatus,
    runtimeEffectiveSyncBackendKind: args.runtimeEffectiveSyncBackendKind,
    syncBackendSaveState: args.syncBackendSaveState,
    setLastSyncRunResult: args.setLastSyncRunResult,
    setSyncLastRunAt: args.setSyncLastRunAt,
    setSyncRunning: args.setSyncRunning,
    setSyncStatusError: args.setSyncStatusError,
    setLastSyncErrorEnvelope: args.setLastSyncErrorEnvelope,
    settingsMountedRef: args.settingsMountedRef,
    syncEnabled: args.syncEnabled,
    syncRunning: args.syncRunning,
    syncBackendConfigs: args.syncBackendConfigs,
    t: args.t,
    format: args.format,
  });
  const { handleSeedFullSync } = useAssistantSyncSeedAction({
    logAssistantSettingsError: args.logAssistantSettingsError,
    refreshSyncStatus,
    runSyncNow,
    seedSyncRunning: args.seedSyncRunning,
    setSeedSyncRunning: args.setSeedSyncRunning,
    settingsMountedRef: args.settingsMountedRef,
    t: args.t,
    format: args.format,
  });

  return {
    availableSyncBackendKinds,
    handleSeedFullSync,
    refreshSyncStatus,
    retrySaveSyncBackend,
    runSyncNow,
    saveSyncBackend,
    selectSyncBackend,
  };
}
