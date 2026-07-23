import { useCallback, type RefObject } from 'react';

import { appendClientErrorLog } from '@/lib/errors/errorLogging';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import type { SyncBackendSupportContext } from '@/lib/syncBackend/model';
import type { AssistantSettingsViewModel } from '../assistant/types';
import type { RefreshErrorLogsResult } from '../data/types';
import { useAssistantMcpController } from './assistant/mcp';
import { useAssistantSyncController } from './assistant/sync';

interface UseAssistantSettingsControllerArgs {
  syncBackendSupport: SyncBackendSupportContext;
  supportsMcpHosting: boolean;
  settingsMountedRef: RefObject<boolean>;
  formatSyncTimestamp: (value: string | null) => string;
  refreshErrorLogs: (silent?: boolean, announce?: boolean) => Promise<RefreshErrorLogsResult | null>;
}

export function useAssistantSettingsController({
  syncBackendSupport,
  supportsMcpHosting,
  settingsMountedRef,
  formatSyncTimestamp,
  refreshErrorLogs,
}: UseAssistantSettingsControllerArgs): AssistantSettingsViewModel {
  const logAssistantSettingsError = useCallback((source: string, message: string, error: unknown) => {
    const details = toIpcErrorMessage(error);
    void appendClientErrorLog(source, message, error, details, 'error')
      .then((appended) => {
        if (appended) {
          void refreshErrorLogs(true);
        }
      });
  }, [refreshErrorLogs]);

  const sync = useAssistantSyncController({
    syncBackendSupport,
    settingsMountedRef,
    formatSyncTimestamp,
    logAssistantSettingsError,
  });
  const mcp = useAssistantMcpController({
    supportsMcpHosting,
    settingsMountedRef,
    logAssistantSettingsError,
  });

  return {
    ready: sync.ready && mcp.ready,
    sync: sync.sync,
    mcp: mcp.mcp,
  };
}
