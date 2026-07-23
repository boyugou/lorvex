import {
  useMemo,
  useState,
} from 'react';
import type { ExportSnapshotResult, ImportSnapshotResult, SnapshotExportCategory } from '@/lib/ipc/settings';
import type { SnapshotStatus } from '@/components/settings/data/types';
import { buildSnapshotPreview } from '@/components/settings/settingsUtils';

import { useDataSnapshotActions } from './snapshot/actions';
import type {
  DataSnapshotControls,
  UseDataSnapshotControlsArgs,
} from './snapshot/support';

export type { DataSnapshotControls } from './snapshot/support';

const DEFAULT_SCOPED_EXPORT_CATEGORIES: SnapshotExportCategory[] = [
  'tasks',
  'lists',
  'calendar',
  'habits',
  'daily_reviews',
  'memory',
  'preferences',
  'focus',
  'subscriptions',
];

export function useDataSnapshotControls({
  settingsMountedRef,
  logDataSettingsError,
}: UseDataSnapshotControlsArgs): DataSnapshotControls {
  const [snapshotFilePath, setSnapshotFilePath] = useState('');
  const [snapshotBusy, setSnapshotBusy] = useState(false);
  const [lastSnapshotResult, setLastSnapshotResult] = useState<ExportSnapshotResult | ImportSnapshotResult | null>(null);
  const [snapshotErrorDetail, setSnapshotErrorDetail] = useState<string | null>(null);
  const [snapshotStatus, setSnapshotStatus] = useState<SnapshotStatus | null>(null);
  const [lastExportPath, setLastExportPath] = useState<string | null>(null);
  const [exportScopeMode, setExportScopeMode] = useState<'full' | 'scoped'>('full');
  const [exportScopeCategories, setExportScopeCategories] = useState<SnapshotExportCategory[]>(
    DEFAULT_SCOPED_EXPORT_CATEGORIES,
  );

  function toggleExportScopeCategory(category: SnapshotExportCategory) {
    setExportScopeCategories((current) =>
      current.includes(category)
        ? current.filter((value) => value !== category)
        : [...current, category],
    );
  }

  const actions = useDataSnapshotActions({
    logDataSettingsError,
    settingsMountedRef,
    setSnapshotBusy,
    setSnapshotErrorDetail,
    setLastSnapshotResult,
    setSnapshotStatus,
    setSnapshotFilePath,
    setLastExportPath,
    exportScopeMode,
    exportScopeCategories,
    snapshotBusy,
    snapshotFilePath,
  });

  const snapshotPreview = useMemo(
    () => buildSnapshotPreview(snapshotFilePath),
    [snapshotFilePath],
  );

  return {
    snapshotBusy,
    lastSnapshotResult,
    snapshotErrorDetail,
    snapshotStatus,
    lastExportPath,
    snapshotPreview,
    exportScopeMode,
    exportScopeCategories,
    setExportScopeMode,
    toggleExportScopeCategory,
    handleExportSnapshot: actions.handleExportSnapshot,
    handleLoadSnapshotFile: actions.handleLoadSnapshotFile,
    handleImportSnapshot: actions.handleImportSnapshot,
  };
}
