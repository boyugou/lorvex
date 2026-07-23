import { useCallback, useMemo } from 'react';

import { listAvailableSyncBackends } from '@/lib/syncBackend/model';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';
import type { UseAssistantSyncActionsArgs } from './types';

interface UseAssistantSyncBackendSelectionArgs {
  syncBackendSupport: UseAssistantSyncActionsArgs['syncBackendSupport'];
  setConfiguredSyncBackendKind: UseAssistantSyncActionsArgs['setConfiguredSyncBackendKind'];
  syncBackendDraftPendingRef: UseAssistantSyncActionsArgs['syncBackendDraftPendingRef'];
}

export function useAssistantSyncBackendSelection({
  syncBackendSupport,
  setConfiguredSyncBackendKind,
  syncBackendDraftPendingRef,
}: UseAssistantSyncBackendSelectionArgs) {
  const availableSyncBackendKinds = useMemo(
    () => listAvailableSyncBackends(syncBackendSupport),
    [syncBackendSupport],
  );

  const selectSyncBackend = useCallback((backendKind: SyncBackendKind) => {
    if (!availableSyncBackendKinds.includes(backendKind)) {
      return;
    }
    syncBackendDraftPendingRef.current = backendKind;
    setConfiguredSyncBackendKind(backendKind);
  }, [
    availableSyncBackendKinds,
    setConfiguredSyncBackendKind,
    syncBackendDraftPendingRef,
  ]);

  return {
    availableSyncBackendKinds,
    selectSyncBackend,
  };
}
