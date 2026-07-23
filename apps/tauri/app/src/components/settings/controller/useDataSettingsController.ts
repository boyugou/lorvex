import type {
  RefObject,
} from 'react';
import type { ErrorLogEntry, ExportSnapshotResult, ImportSnapshotResult, SnapshotExportCategory } from '@/lib/ipc/settings';
import type {
  RecentLogItem,
  RefreshErrorLogsResult,
  SnapshotStatus,
} from '../data/types';
import { buildSnapshotPreview } from '../settingsUtils';
import {
  useDataDiagnosticsControls,
} from './data/diagnostics';
import {
  useDataSnapshotControls,
} from './data/snapshot';

interface UseDataSettingsControllerArgs {
  settingsMountedRef: RefObject<boolean>;
}

export interface DataSettingsController {
  snapshotBusy: boolean;
  lastSnapshotResult: ExportSnapshotResult | ImportSnapshotResult | null;
  snapshotErrorDetail: string | null;
  snapshotStatus: SnapshotStatus | null;
  lastExportPath: string | null;
  snapshotPreview: ReturnType<typeof buildSnapshotPreview>;
  exportScopeMode: 'full' | 'scoped';
  exportScopeCategories: SnapshotExportCategory[];
  setExportScopeMode: (value: 'full' | 'scoped') => void;
  toggleExportScopeCategory: (category: SnapshotExportCategory) => void;
  errorLogs: ErrorLogEntry[];
  errorLogsBusy: boolean;
  errorLogsActionMessage: string | null;
  recentLogsActionMessage: string | null;
  recentLogs: RecentLogItem[];
  setErrorLogsActionMessage: (message: string | null) => void;
  refreshErrorLogs: (silent?: boolean, announce?: boolean) => Promise<RefreshErrorLogsResult | null>;
  handleExportSnapshot: () => Promise<void>;
  handleLoadSnapshotFile: () => Promise<void>;
  handleImportSnapshot: () => Promise<void>;
  handleRefreshErrorLogs: (announce?: boolean) => Promise<void>;
  handleCopyErrorLogs: () => Promise<void>;
  handleClearErrorLogs: () => Promise<void>;
  handleCopyRecentLogs: () => Promise<void>;
  handleRetrySyncOutboxEntry: (id: string) => Promise<void>;
  /** Update the diagnostics filter intent backing `refreshErrorLogs`.
   * The refresh layer resolves rolling time windows at call time so the
   * active preset stays current while the panel remains open. */
  setDiagnosticsFilters: (filters: {
    timeWindow: 'hour' | 'day' | 'week' | 'all';
    sourceDeviceId: string | null;
  }) => void;
}

export function useDataSettingsController({
  settingsMountedRef,
}: UseDataSettingsControllerArgs): DataSettingsController {
  const diagnostics = useDataDiagnosticsControls({
    settingsMountedRef,
  });
  const snapshotControls = useDataSnapshotControls({
    settingsMountedRef,
    logDataSettingsError: diagnostics.logDataSettingsError,
  });

  return {
    snapshotBusy: snapshotControls.snapshotBusy,
    lastSnapshotResult: snapshotControls.lastSnapshotResult,
    snapshotErrorDetail: snapshotControls.snapshotErrorDetail,
    snapshotStatus: snapshotControls.snapshotStatus,
    lastExportPath: snapshotControls.lastExportPath,
    snapshotPreview: snapshotControls.snapshotPreview,
    exportScopeMode: snapshotControls.exportScopeMode,
    exportScopeCategories: snapshotControls.exportScopeCategories,
    setExportScopeMode: snapshotControls.setExportScopeMode,
    toggleExportScopeCategory: snapshotControls.toggleExportScopeCategory,
    errorLogs: diagnostics.errorLogs,
    errorLogsBusy: diagnostics.errorLogsBusy,
    errorLogsActionMessage: diagnostics.errorLogsActionMessage,
    recentLogsActionMessage: diagnostics.recentLogsActionMessage,
    recentLogs: diagnostics.recentLogs,
    setErrorLogsActionMessage: diagnostics.setErrorLogsActionMessage,
    refreshErrorLogs: diagnostics.refreshErrorLogs,
    handleExportSnapshot: snapshotControls.handleExportSnapshot,
    handleLoadSnapshotFile: snapshotControls.handleLoadSnapshotFile,
    handleImportSnapshot: snapshotControls.handleImportSnapshot,
    handleRefreshErrorLogs: diagnostics.handleRefreshErrorLogs,
    handleCopyErrorLogs: diagnostics.handleCopyErrorLogs,
    handleClearErrorLogs: diagnostics.handleClearErrorLogs,
    handleCopyRecentLogs: diagnostics.handleCopyRecentLogs,
    handleRetrySyncOutboxEntry: diagnostics.handleRetrySyncOutboxEntry,
    setDiagnosticsFilters: diagnostics.setDiagnosticsFilters,
  };
}
