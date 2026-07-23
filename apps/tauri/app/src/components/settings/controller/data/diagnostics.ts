import { useI18n } from '@/lib/i18n';
import { useDataDiagnosticsActions } from './diagnostics/actions';
import { useRecentLogs } from './diagnostics/recentLogs';
import { useDataDiagnosticsRefresh } from './diagnostics/refresh';
import type {
  DataDiagnosticsControls,
  UseDataDiagnosticsControlsArgs,
} from './diagnostics/types';

export type {
  DataDiagnosticsControls,
  UseDataDiagnosticsControlsArgs,
} from './diagnostics/types';

export function useDataDiagnosticsControls({
  settingsMountedRef,
}: UseDataDiagnosticsControlsArgs): DataDiagnosticsControls {
  const { t } = useI18n();
  const refresh = useDataDiagnosticsRefresh({
    settingsMountedRef,
    t,
  });
  const recentLogs = useRecentLogs({
    changelogEntries: refresh.changelogEntries,
    errorLogs: refresh.errorLogs,
    recentSyncEvents: refresh.recentSyncEvents,
  });
  const actions = useDataDiagnosticsActions({
    errorLogs: refresh.errorLogs,
    errorLogsBusy: refresh.errorLogsBusy,
    logDataSettingsError: refresh.logDataSettingsError,
    recentLogs,
    refreshErrorLogs: refresh.refreshErrorLogs,
    setErrorLogsActionMessage: refresh.setErrorLogsActionMessage,
    setRecentLogsActionMessage: refresh.setRecentLogsActionMessage,
    setErrorLogsBusy: refresh.setErrorLogsBusy,
    settingsMountedRef,
    t,
  });

  return {
    errorLogs: refresh.errorLogs,
    errorLogsBusy: refresh.errorLogsBusy,
    errorLogsActionMessage: refresh.errorLogsActionMessage,
    recentLogsActionMessage: refresh.recentLogsActionMessage,
    recentLogs,
    setErrorLogsActionMessage: refresh.setErrorLogsActionMessage,
    setRecentLogsActionMessage: refresh.setRecentLogsActionMessage,
    refreshErrorLogs: refresh.refreshErrorLogs,
    logDataSettingsError: refresh.logDataSettingsError,
    handleRefreshErrorLogs: actions.handleRefreshErrorLogs,
    handleCopyErrorLogs: actions.handleCopyErrorLogs,
    handleClearErrorLogs: actions.handleClearErrorLogs,
    handleCopyRecentLogs: actions.handleCopyRecentLogs,
    handleRetrySyncOutboxEntry: actions.handleRetrySyncOutboxEntry,
    setDiagnosticsFilters: refresh.setDiagnosticsFilters,
  };
}
