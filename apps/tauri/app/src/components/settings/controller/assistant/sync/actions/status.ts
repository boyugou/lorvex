import { useCallback } from 'react';

import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import { getPendingOutboxEntries, getSyncStatus } from '@/lib/ipc/sync';
import type { UseAssistantSyncActionsArgs } from './types';

interface UseAssistantSyncStatusActionsArgs {
  setSyncLastRunAt: UseAssistantSyncActionsArgs['setSyncLastRunAt'];
  setSyncPendingPreview: UseAssistantSyncActionsArgs['setSyncPendingPreview'];
  setSyncStatus: UseAssistantSyncActionsArgs['setSyncStatus'];
  setSyncStatusError: UseAssistantSyncActionsArgs['setSyncStatusError'];
  setConfiguredSyncBackendKind: UseAssistantSyncActionsArgs['setConfiguredSyncBackendKind'];
  settingsMountedRef: UseAssistantSyncActionsArgs['settingsMountedRef'];
  syncBackendDraftPendingRef: UseAssistantSyncActionsArgs['syncBackendDraftPendingRef'];
}

export function useAssistantSyncStatusActions({
  setSyncLastRunAt,
  setSyncPendingPreview,
  setSyncStatus,
  setSyncStatusError,
  setConfiguredSyncBackendKind,
  settingsMountedRef,
  syncBackendDraftPendingRef,
}: UseAssistantSyncStatusActionsArgs) {
  const refreshSyncStatus = useCallback(async () => {
    try {
      const [status, pending] = await Promise.all([
        getSyncStatus(),
        getPendingOutboxEntries(5),
      ]);
      if (!settingsMountedRef.current) return;
      setSyncStatus(status);
      setSyncPendingPreview(pending);
      // Initialize syncLastRunAt from the DB status so the UI doesn't show
      // "never synced" after app restart when sync has actually run.
      if (status.last_synced_at) {
        setSyncLastRunAt(status.last_synced_at);
      }
      if (syncBackendDraftPendingRef.current === null) {
        setConfiguredSyncBackendKind(status.sync_backend_kind as SyncBackendKind | null);
      }
      setSyncStatusError(null);
    } catch (error) {
      if (!settingsMountedRef.current) return;
      setSyncStatusError(toIpcErrorMessage(error));
    }
  }, [
    setSyncLastRunAt,
    setSyncPendingPreview,
    setSyncStatus,
    setSyncStatusError,
    setConfiguredSyncBackendKind,
    settingsMountedRef,
    syncBackendDraftPendingRef,
  ]);

  return {
    refreshSyncStatus,
  };
}
