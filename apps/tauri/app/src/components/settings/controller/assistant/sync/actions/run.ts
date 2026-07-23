import { useCallback, useEffect, useRef } from 'react';

import {
  buildSyncBackendConfig,
  syncBackendUsesFilesystemRootPathEditor,
  type SyncBackendConfigs,
} from '@/lib/syncBackend/model';
import { runSyncBackendNow } from '@/lib/syncBackend/runtime';
import { parseSyncErrorEnvelope } from '@/lib/syncBackend/errorKind';
import { toast } from '@/lib/notifications/toast';
import { buildSyncErrorPresentation } from './errorToast';
import type { UseAssistantSyncActionsArgs } from './types';
import type { SyncBackendSaveState } from '../types';

interface UseAssistantSyncRunNowActionArgs {
  logAssistantSettingsError: UseAssistantSyncActionsArgs['logAssistantSettingsError'];
  refreshSyncStatus: () => Promise<void>;
  runtimeEffectiveSyncBackendKind: UseAssistantSyncActionsArgs['runtimeEffectiveSyncBackendKind'];
  syncBackendSaveState: SyncBackendSaveState;
  setLastSyncRunResult: UseAssistantSyncActionsArgs['setLastSyncRunResult'];
  setSyncLastRunAt: UseAssistantSyncActionsArgs['setSyncLastRunAt'];
  setSyncRunning: UseAssistantSyncActionsArgs['setSyncRunning'];
  setSyncStatusError: UseAssistantSyncActionsArgs['setSyncStatusError'];
  setLastSyncErrorEnvelope: UseAssistantSyncActionsArgs['setLastSyncErrorEnvelope'];
  settingsMountedRef: UseAssistantSyncActionsArgs['settingsMountedRef'];
  syncEnabled: UseAssistantSyncActionsArgs['syncEnabled'];
  syncRunning: UseAssistantSyncActionsArgs['syncRunning'];
  syncBackendConfigs: SyncBackendConfigs;
  t: UseAssistantSyncActionsArgs['t'];
  format: UseAssistantSyncActionsArgs['format'];
}

export function useAssistantSyncRunNowAction({
  logAssistantSettingsError,
  refreshSyncStatus,
  runtimeEffectiveSyncBackendKind,
  syncBackendSaveState,
  setLastSyncRunResult,
  setSyncLastRunAt,
  setSyncRunning,
  setSyncStatusError,
  setLastSyncErrorEnvelope,
  settingsMountedRef,
  syncEnabled,
  syncRunning,
  syncBackendConfigs,
  t,
  format,
}: UseAssistantSyncRunNowActionArgs) {
  // a Retry button on the actionable error toast needs to
  // invoke the same `runSyncNow` that fired the failing request. A ref
  // lets the stable callback identity survive re-renders without
  // dragging `runSyncNow` back into its own dependency array.
  const runSyncNowRef = useRef<(() => Promise<void>) | null>(null);
  const runSyncNow = useCallback(async () => {
    if (syncRunning) return;
    if (!syncEnabled) {
      toast.info(t('settings.syncEnableFirst'));
      return;
    }
    if (syncBackendSaveState === 'saving') {
      toast.info(t('common.saving'));
      return;
    }
    if (syncBackendSaveState === 'error') {
      toast.info(t('settings.autosaveError'));
      return;
    }
    if (runtimeEffectiveSyncBackendKind === null) {
      toast.info(t('settings.syncNotAvailableOnDevice'));
      return;
    }
    const activeBackend = buildSyncBackendConfig({
      backendKind: runtimeEffectiveSyncBackendKind,
      backendConfigs: syncBackendConfigs,
    });
    if (!activeBackend) {
      toast.info(t('settings.syncNotAvailableOnDevice'));
      return;
    }
    const rootPath = activeBackend.kind === 'filesystem_bridge'
      ? activeBackend.config.rootPath.trim()
      : '';
    if (syncBackendUsesFilesystemRootPathEditor(runtimeEffectiveSyncBackendKind) && !rootPath) {
      toast.info(t('settings.syncSharedFolderPathRequired'));
      return;
    }

    // Filesystem-bridge sync can appear to succeed locally while the backing
    // provider is offline. Short-circuit with an actionable message when the
    // browser is offline so the user does not wait on provider-specific
    // retries without feedback.
    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
      toast.info(t('settings.syncOfflinePreflight'));
      return;
    }

    setSyncRunning(true);
    toast.info(t('settings.syncStarted'));

    // Fire-and-forget: don't block the UI waiting for network I/O.
    // The sync command runs on Tauri's thread pool. We poll status to update the UI.
    runSyncBackendNow({
      backend: activeBackend,
      maxEvents: 500,
    }).then((result) => {
      if (!settingsMountedRef.current) return;
      setLastSyncRunResult(result);
      setSyncLastRunAt(new Date().toISOString());
      setSyncRunning(false);
      // a successful run clears any stale actionable
      // error envelope so the card's inline remediation row
      // disappears once the problem is fixed.
      setLastSyncErrorEnvelope(null);
      setSyncStatusError(null);
      void refreshSyncStatus();
      toast.success(
        `${t('settings.syncSummaryPushed')}: ${result.summary.pushed} · ${t('settings.syncSummaryPulled')}: ${result.summary.pulledRemoteEvents} · ${t('settings.syncSummaryApplied')}: ${result.summary.applied}`,
      );
    }).catch((error: unknown) => {
      logAssistantSettingsError('frontend.settings.sync.run', 'Run sync now failed', error);
      // parse the typed envelope emitted by the Rust
      // sync commands and dispatch an actionable toast (Retry / Open
      // System Settings / Open docs) per-kind. Malformed failures use
      // the localized unknown presentation instead of preserving raw
      // backend text.
      const envelope = parseSyncErrorEnvelope(error);
      const presentation = buildSyncErrorPresentation({
        envelope,
        t,
        format,
        retry: () => {
          void runSyncNowRef.current?.();
        },
      });
      if (settingsMountedRef.current) {
        setSyncStatusError(envelope.message || presentation.message);
        setLastSyncErrorEnvelope(envelope);
        setSyncRunning(false);
      }
      if (presentation.kind === 'unknown') {
        toast.error(presentation.message);
        return;
      }
      if (presentation.action) {
        toast.error(
          presentation.message,
          presentation.action,
          presentation.priority ? { priority: true } : undefined,
        );
      } else {
        toast.error(presentation.message);
      }
    });
  }, [
    logAssistantSettingsError,
    refreshSyncStatus,
    runtimeEffectiveSyncBackendKind,
    setLastSyncRunResult,
    setSyncLastRunAt,
    setSyncRunning,
    setSyncStatusError,
    setLastSyncErrorEnvelope,
    settingsMountedRef,
    syncEnabled,
    syncRunning,
    syncBackendSaveState,
    syncBackendConfigs,
    t,
    format,
  ]);

  useEffect(() => {
    runSyncNowRef.current = runSyncNow;
  }, [runSyncNow]);

  return { runSyncNow };
}
