import { useCallback } from 'react';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import { exportDataSnapshot } from '@/lib/ipc/settings';
import type { useI18n } from '@/lib/i18n';
import { toast } from '@/lib/notifications/toast';
import { extractSnapshotFileName } from '@/components/settings/settingsUtils';

import type { SnapshotActionArgs } from '../support';

type SnapshotTranslator = ReturnType<typeof useI18n>['t'];
type SnapshotFormatter = ReturnType<typeof useI18n>['format'];

interface PayloadActionArgs extends Pick<
  SnapshotActionArgs,
  | 'logDataSettingsError'
  | 'exportScopeCategories'
  | 'exportScopeMode'
  | 'setSnapshotBusy'
  | 'setSnapshotErrorDetail'
  | 'setLastSnapshotResult'
  | 'setSnapshotStatus'
  | 'setSnapshotFilePath'
  | 'setLastExportPath'
  | 'settingsMountedRef'
  | 'snapshotBusy'
> {
  t: SnapshotTranslator;
  format: SnapshotFormatter;
}

/** Build a default filename with a UTC timestamp. */
function buildDefaultExportFilename(): string {
  const now = new Date();
  const stamp = now.toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');
  return `lorvex-export-v1-${stamp}.zip`;
}

export function useSnapshotPayloadActions({
  logDataSettingsError,
  setSnapshotBusy,
  setSnapshotErrorDetail,
  setLastSnapshotResult,
  setSnapshotStatus,
  setSnapshotFilePath,
  setLastExportPath,
  settingsMountedRef,
  exportScopeCategories,
  exportScopeMode,
  snapshotBusy,
  t,
  format,
}: PayloadActionArgs) {
  const handleExportSnapshot = useCallback(async () => {
    if (snapshotBusy) return;
    if (exportScopeMode === 'scoped' && exportScopeCategories.length === 0) {
      setSnapshotStatus({ tone: 'info', message: t('settings.exportPickScope') });
      toast.info(t('settings.exportPickScope'));
      return;
    }

    // Open a native save dialog so the user chooses where to save the export.
    // lazy-import plugin-dialog so the plugin JS only
    // loads when the user actually opens Settings → Data and clicks
    // export / import.
    const { save } = await import('@tauri-apps/plugin-dialog');
    const chosenPath = await save({
      title: t('settings.exportSaveDialogTitle'),
      defaultPath: buildDefaultExportFilename(),
      filters: [{ name: 'ZIP Archive', extensions: ['zip'] }],
    });

    // User cancelled the dialog.
    if (!chosenPath) return;

    setSnapshotBusy(true);
    setSnapshotErrorDetail(null);
    setLastExportPath(null);
    try {
      const result = await exportDataSnapshot(
        chosenPath,
        exportScopeMode === 'scoped' ? exportScopeCategories : undefined,
      );
      if (!settingsMountedRef.current) return;
      setLastSnapshotResult(result);
      setLastExportPath(result.export_path);
      const exportFileName = extractSnapshotFileName(result.export_path) ?? result.export_path;
      const successMessage = format('settings.exportSavedToPath', { path: exportFileName });
      setSnapshotStatus({
        tone: 'success',
        message: successMessage,
      });
      toast.success(successMessage);
    } catch (error) {
      logDataSettingsError('frontend.settings.data.export', 'Data export failed', error);
      if (settingsMountedRef.current) {
        setSnapshotErrorDetail(toIpcErrorMessage(error));
        setSnapshotStatus({ tone: 'error', message: t('settings.exportFailed') });
        setLastExportPath(null);
      }
      // surface the backend reason (disk-full, missing
      // directory, permission denied) rather than a bare "Export failed".
      toast.errorWithDetail(error, t('settings.exportFailed'));
    } finally {
      if (settingsMountedRef.current) {
        setSnapshotBusy(false);
      }
    }
  }, [
    logDataSettingsError,
    setSnapshotBusy,
    setSnapshotErrorDetail,
    setLastSnapshotResult,
    setSnapshotStatus,
    setLastExportPath,
    settingsMountedRef,
    exportScopeCategories,
    exportScopeMode,
    snapshotBusy,
    t,
    format,
  ]);

  const handleLoadSnapshotFile = useCallback(async () => {
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const filePath = await open({
        title: t('settings.importOpenDialogTitle'),
        filters: [{ name: 'ZIP', extensions: ['zip'] }],
      });

      // User cancelled the dialog.
      if (!filePath) return;
      if (!settingsMountedRef.current) return;

      const fileName = extractSnapshotFileName(filePath) ?? filePath;
      setSnapshotFilePath(filePath);
      setLastSnapshotResult(null);
      setSnapshotErrorDetail(null);
      setSnapshotStatus({
        tone: 'success',
        message: `${t('settings.importLoadedFile')}: ${fileName}`,
      });
    } catch (error) {
      logDataSettingsError('frontend.settings.data.file_load', 'Failed to load import file', error);
      if (settingsMountedRef.current) {
        setSnapshotErrorDetail(toIpcErrorMessage(error));
        setSnapshotStatus({ tone: 'error', message: t('settings.importLoadFileFailed') });
      }
      // the native file dialog can fail for permission or
      // sandbox reasons — surface those rather than a bare fallback.
      toast.errorWithDetail(error, t('settings.importLoadFileFailed'));
    }
  }, [
    logDataSettingsError,
    setSnapshotErrorDetail,
    setSnapshotFilePath,
    setLastSnapshotResult,
    setSnapshotStatus,
    settingsMountedRef,
    t,
  ]);

  return {
    handleExportSnapshot,
    handleLoadSnapshotFile,
  };
}
