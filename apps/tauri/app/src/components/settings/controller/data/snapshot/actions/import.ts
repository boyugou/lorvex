import { useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import { importDataSnapshot } from '@/lib/ipc/settings';
import type { useI18n } from '@/lib/i18n';
import { toast } from '@/lib/notifications/toast';
import { invalidateAllAfterSnapshotImport } from '@/components/settings/settingsUtils';

import {
  getImportedTotal,
  type SnapshotActionArgs,
} from '../support';

type SnapshotTranslator = ReturnType<typeof useI18n>['t'];

interface ImportActionArgs extends Pick<
  SnapshotActionArgs,
  | 'logDataSettingsError'
  | 'setSnapshotBusy'
  | 'setSnapshotErrorDetail'
  | 'setLastSnapshotResult'
  | 'setSnapshotStatus'
  | 'settingsMountedRef'
  | 'snapshotBusy'
  | 'snapshotFilePath'
> {
  t: SnapshotTranslator;
}

export function useSnapshotImportAction({
  logDataSettingsError,
  setSnapshotBusy,
  setSnapshotErrorDetail,
  setLastSnapshotResult,
  setSnapshotStatus,
  settingsMountedRef,
  snapshotBusy,
  snapshotFilePath,
  t,
}: ImportActionArgs) {
  const qc = useQueryClient();

  return useCallback(async () => {
    if (snapshotBusy) return;
    const filePath = snapshotFilePath.trim();
    if (!filePath) {
      setSnapshotStatus({ tone: 'info', message: t('settings.importNeedInput') });
      toast.info(t('settings.importNeedInput'));
      return;
    }
    setSnapshotBusy(true);
    setSnapshotErrorDetail(null);
    try {
      const result = await importDataSnapshot(filePath);
      if (!settingsMountedRef.current) return;
      setLastSnapshotResult(result);
      const blockingFindings = result.validation_findings.filter((finding) => finding.severity === 'error');
      if (blockingFindings.length > 0) {
        setSnapshotErrorDetail(blockingFindings.map((finding) => finding.message).join('\n'));
        setSnapshotStatus({ tone: 'error', message: t('settings.importFailed') });
        toast.error(t('settings.importFailed'));
        return;
      }
      invalidateAllAfterSnapshotImport(qc);
      const importedTotal = getImportedTotal(result);
      if (importedTotal === 0) {
        setSnapshotStatus({ tone: 'info', message: t('settings.importNoChanges') });
        toast.info(t('settings.importNoChanges'));
      } else {
        setSnapshotStatus({ tone: 'success', message: t('settings.importSuccess') });
        toast.success(t('settings.importSuccess'));
      }
    } catch (error) {
      logDataSettingsError('frontend.settings.data.import', 'Data import failed', error);
      if (settingsMountedRef.current) {
        setSnapshotErrorDetail(toIpcErrorMessage(error));
        setSnapshotStatus({ tone: 'error', message: t('settings.importFailed') });
      }
      // surface the underlying import failure (schema
      // mismatch, corrupt zip, disk-full) in the toast so the user
      // isn't left staring at a bare "Import failed" string.
      toast.errorWithDetail(error, t('settings.importFailed'));
    } finally {
      if (settingsMountedRef.current) {
        setSnapshotBusy(false);
      }
    }
  }, [
    logDataSettingsError,
    qc,
    setSnapshotBusy,
    setSnapshotErrorDetail,
    setLastSnapshotResult,
    setSnapshotStatus,
    settingsMountedRef,
    snapshotBusy,
    snapshotFilePath,
    t,
  ]);
}
