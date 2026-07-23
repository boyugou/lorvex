import { useCallback } from 'react';

import { confirm } from '@/lib/dialogs/confirm';
import { safeWriteToClipboard } from '@/lib/platform/safeClipboard';
import { toast } from '@/lib/notifications/toast';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import { clearErrorLogs } from '@/lib/ipc/settings';
import { resetOutboxEntryRetryCount } from '@/lib/ipc/sync';
import type { UseDataDiagnosticsActionsArgs } from './types';

export function useDataDiagnosticsActions({
  errorLogs,
  errorLogsBusy,
  logDataSettingsError,
  recentLogs,
  refreshErrorLogs,
  setErrorLogsActionMessage,
  setRecentLogsActionMessage,
  setErrorLogsBusy,
  settingsMountedRef,
  t,
}: UseDataDiagnosticsActionsArgs) {
  const handleRefreshErrorLogs = useCallback(async (announce = true) => {
    await refreshErrorLogs(false, announce);
  }, [refreshErrorLogs]);

  const handleCopyErrorLogs = useCallback(async () => {
    if (errorLogs.length === 0) {
      setErrorLogsActionMessage(t('settings.errorLogsEmpty'));
      return;
    }
    const payload = errorLogs
      .map((entry) => [
        `[${entry.created_at}]`,
        `[${entry.level}]`,
        `[${entry.source}]`,
        entry.message,
        entry.details ? `\n${entry.details}` : '',
      ].join(' '))
      .join('\n\n');
    const result = await safeWriteToClipboard(payload, 'frontend.settings.error_logs.copy');
    if (!result.ok) {
      logDataSettingsError('frontend.settings.error_logs.copy', 'Copy error logs failed', result.error);
      setErrorLogsActionMessage(`${t('common.error')}: ${toIpcErrorMessage(result.error)}`);
      // surface the recovery hint when the helper detects a
      // permission/sandbox failure so users have a manual fallback.
      toast.errorWithDetail(result.error, t('settings.clipboardCopyFailed'));
      if (result.recoveryHint) {
        toast.info(t('settings.clipboardCopyHint'));
      }
      return;
    }
    setErrorLogsActionMessage(t('settings.errorLogsCopied'));
    toast.success(t('settings.errorLogsCopied'));
  }, [errorLogs, logDataSettingsError, setErrorLogsActionMessage, t]);

  const handleCopyRecentLogs = useCallback(async () => {
    if (recentLogs.length === 0) {
      setRecentLogsActionMessage(t('settings.recentLogsEmpty'));
      return;
    }
    const payload = recentLogs
      .map((entry) => [
        `[${entry.timestamp}]`,
        `[${entry.level}]`,
        `[${entry.source}]`,
        entry.summary,
        entry.details ? `\n${entry.details}` : '',
      ].join(' '))
      .join('\n\n');
    const result = await safeWriteToClipboard(payload, 'frontend.settings.recent_logs.copy');
    if (!result.ok) {
      logDataSettingsError('frontend.settings.recent_logs.copy', 'Copy recent logs failed', result.error);
      setRecentLogsActionMessage(`${t('common.error')}: ${toIpcErrorMessage(result.error)}`);
      // same recovery-hint handling as `handleCopyErrorLogs`.
      toast.errorWithDetail(result.error, t('settings.clipboardCopyFailed'));
      if (result.recoveryHint) {
        toast.info(t('settings.clipboardCopyHint'));
      }
      return;
    }
    setRecentLogsActionMessage(t('settings.recentLogsCopied'));
    toast.success(t('settings.recentLogsCopied'));
  }, [logDataSettingsError, recentLogs, setRecentLogsActionMessage, t]);

  const handleClearErrorLogs = useCallback(async () => {
    if (errorLogsBusy) return;
    const confirmed = await confirm({
      title: t('settings.errorLogsClear'),
      message: t('settings.errorLogsClearConfirm'),
      variant: 'danger',
    });
    if (!confirmed) return;
    setErrorLogsBusy(true);
    try {
      const result = await clearErrorLogs();
      const refreshed = await refreshErrorLogs(true, true);
      const recentCount = refreshed?.recentCount ?? 0;
      const message = `${t('settings.errorLogsCleared')}: ${result.deleted}`;
      if (settingsMountedRef.current) {
        setErrorLogsActionMessage(message);
      }
      toast.success(message);
      if (recentCount > 0) {
        toast.info(`${t('settings.errorLogsScopeHint')} (${t('settings.recentLogsTitle')}: ${recentCount})`);
      }
    } catch (error) {
      logDataSettingsError('frontend.settings.error_logs.clear', 'Clear error logs failed', error);
      const message = `${t('common.error')}: ${toIpcErrorMessage(error)}`;
      if (settingsMountedRef.current) {
        setErrorLogsActionMessage(message);
      }
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (settingsMountedRef.current) {
        setErrorLogsBusy(false);
      }
    }
  }, [
    errorLogsBusy,
    logDataSettingsError,
    refreshErrorLogs,
    setErrorLogsActionMessage,
    setErrorLogsBusy,
    settingsMountedRef,
    t,
  ]);

  const handleRetrySyncOutboxEntry = useCallback(async (id: string) => {
    if (errorLogsBusy) return;
    setErrorLogsBusy(true);
    try {
      await resetOutboxEntryRetryCount(id);
      const refreshed = await refreshErrorLogs(false);
      if (refreshed === null) {
        const message = t('settings.recentLogsRetrySyncEntryRefreshFailed');
        if (settingsMountedRef.current) {
          setRecentLogsActionMessage(message);
        }
        toast.error(message);
        return;
      }
      const message = t('settings.recentLogsRetrySyncEntryDone');
      if (settingsMountedRef.current) {
        setRecentLogsActionMessage(message);
      }
      toast.success(message);
    } catch (error) {
      logDataSettingsError(
        'frontend.settings.recent_logs.retry_sync_outbox_entry',
        'Retry sync outbox entry failed',
        error,
      );
      const message = `${t('settings.recentLogsRetrySyncEntryFailed')}: ${toIpcErrorMessage(error)}`;
      if (settingsMountedRef.current) {
        setRecentLogsActionMessage(message);
      }
      toast.errorWithDetail(error, t('settings.recentLogsRetrySyncEntryFailed'));
    } finally {
      if (settingsMountedRef.current) {
        setErrorLogsBusy(false);
      }
    }
  }, [
    errorLogsBusy,
    logDataSettingsError,
    refreshErrorLogs,
    setRecentLogsActionMessage,
    setErrorLogsBusy,
    settingsMountedRef,
    t,
  ]);

  return {
    handleClearErrorLogs,
    handleCopyErrorLogs,
    handleCopyRecentLogs,
    handleRefreshErrorLogs,
    handleRetrySyncOutboxEntry,
  };
}
