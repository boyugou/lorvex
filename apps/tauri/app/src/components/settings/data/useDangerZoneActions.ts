import { useCallback, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { clearChangelog, purgeCancelledTasks, resetAllData, resetPreferences } from '@/lib/ipc/settings';
import { useI18n } from '@/lib/i18n';
import {
  invalidateAllQueries,
  invalidateChangelogQueries,
  invalidateTaskWorkspaceQueries,
} from '@/lib/query/queryKeys';
import { clearAllDrafts } from '@/lib/storage/drafts';
import { toast } from '@/lib/notifications/toast';
import { confirm } from '@/lib/dialogs/confirm';
import {
  createBrowserDangerZoneResetTimerHost,
  scheduleDangerZoneResetReload,
} from './dangerZoneActions.runtime';

const RESET_RELOAD_DELAY_MS = 800;
const dangerZoneResetTimerHost = createBrowserDangerZoneResetTimerHost();

function reloadAfterReset() {
  scheduleDangerZoneResetReload(RESET_RELOAD_DELAY_MS, () => {
    window.location.reload();
  }, dangerZoneResetTimerHost);
}

export function useDangerZoneActions() {
  const { t, format } = useI18n();
  const queryClient = useQueryClient();
  const [confirmText, setConfirmText] = useState('');
  const [showResetConfirm, setShowResetConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [purgeBusy, setPurgeBusy] = useState(false);
  const [clearChangelogBusy, setClearChangelogBusy] = useState(false);

  const handleResetPreferences = useCallback(async () => {
    const confirmed = await confirm({
      title: t('settings.dangerResetPrefs'),
      message: t('settings.dangerResetPrefsDesc'),
      confirmLabel: t('settings.dangerResetPrefsAction'),
      cancelLabel: t('common.cancel'),
      variant: 'danger',
    });
    if (!confirmed) return;

    setBusy(true);
    try {
      await resetPreferences();
      toast.success(t('settings.dangerResetPrefsDone'));
      invalidateAllQueries(queryClient);
      reloadAfterReset();
    } catch (error) {
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      setBusy(false);
    }
  }, [queryClient, t]);

  const handleResetAll = useCallback(async () => {
    // the confirmation token is i18n-driven. The
    // localized translation (`settings.dangerResetAllConfirmToken`) is
    // sent verbatim to the backend, which now accepts a small
    // allowlist of localized variants ("DELETE", "删除", "刪除", …)
    // alongside the legacy English literal. Matches the gating
    // already applied in `DangerZonePanel.tsx`.
    const token = t('settings.dangerResetAllConfirmToken');
    if (confirmText !== token) return;

    setBusy(true);
    try {
      await resetAllData(token);
      toast.success(t('settings.dangerResetAllDone'));
      clearAllDrafts();
      invalidateAllQueries(queryClient);
      reloadAfterReset();
    } catch (error) {
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      setBusy(false);
      setShowResetConfirm(false);
      setConfirmText('');
    }
  }, [confirmText, queryClient, t]);

  const dismissResetConfirm = useCallback(() => {
    setShowResetConfirm(false);
    setConfirmText('');
  }, []);

  const handlePurgeCancelled = useCallback(async () => {
    const confirmed = await confirm({
      title: t('settings.purgeCancelled'),
      message: t('settings.purgeCancelledConfirm'),
      variant: 'danger',
      confirmLabel: t('settings.purgeCancelled'),
    });
    if (!confirmed) return;

    setPurgeBusy(true);
    try {
      const result = await purgeCancelledTasks();
      toast.success(format('settings.purgeCancelledResult', { count: result.purged_count }));
      invalidateTaskWorkspaceQueries(queryClient);
    } catch (error) {
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      setPurgeBusy(false);
    }
  }, [format, queryClient, t]);

  // "Clear AI changelog" is also exposed on the Changelog
  // view (that's the primary feature-level action). Mirroring it in the
  // Danger Zone makes the destructive-actions index complete.
  const handleClearChangelog = useCallback(async () => {
    const confirmed = await confirm({
      title: t('settings.dangerClearChangelog'),
      message: t('settings.dangerClearChangelogConfirm'),
      variant: 'danger',
      confirmLabel: t('settings.dangerClearChangelog'),
    });
    if (!confirmed) return;

    setClearChangelogBusy(true);
    try {
      const result = await clearChangelog();
      toast.success(format('settings.dangerClearChangelogDoneCount', { count: result.deleted }));
      invalidateChangelogQueries(queryClient);
    } catch (error) {
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      setClearChangelogBusy(false);
    }
  }, [format, queryClient, t]);

  return {
    busy,
    purgeBusy,
    clearChangelogBusy,
    confirmText,
    showResetConfirm,
    setConfirmText,
    setShowResetConfirm,
    dismissResetConfirm,
    handleResetAll,
    handleResetPreferences,
    handlePurgeCancelled,
    handleClearChangelog,
  };
}
