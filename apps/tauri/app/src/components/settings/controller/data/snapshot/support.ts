import type {
  Dispatch,
  RefObject,
  SetStateAction,
} from 'react';
import type { ExportSnapshotResult, ImportSnapshotResult, SnapshotExportCategory } from '@/lib/ipc/settings';
import type { SnapshotStatus } from '@/components/settings/data/types';
import type { buildSnapshotPreview } from '@/components/settings/settingsUtils';

export interface DataSnapshotControls {
  snapshotBusy: boolean;
  lastSnapshotResult: ExportSnapshotResult | ImportSnapshotResult | null;
  snapshotErrorDetail: string | null;
  snapshotStatus: SnapshotStatus | null;
  lastExportPath: string | null;
  snapshotPreview: ReturnType<typeof buildSnapshotPreview>;
  exportScopeMode: 'full' | 'scoped';
  exportScopeCategories: SnapshotExportCategory[];
  setExportScopeMode: Dispatch<SetStateAction<'full' | 'scoped'>>;
  toggleExportScopeCategory: (category: SnapshotExportCategory) => void;
  handleExportSnapshot: () => Promise<void>;
  handleLoadSnapshotFile: () => Promise<void>;
  handleImportSnapshot: () => Promise<void>;
}

export interface UseDataSnapshotControlsArgs {
  settingsMountedRef: RefObject<boolean>;
  logDataSettingsError: (source: string, message: string, error: unknown) => void;
}

export interface SnapshotActionArgs {
  logDataSettingsError: UseDataSnapshotControlsArgs['logDataSettingsError'];
  settingsMountedRef: RefObject<boolean>;
  setSnapshotBusy: Dispatch<SetStateAction<boolean>>;
  setSnapshotErrorDetail: Dispatch<SetStateAction<string | null>>;
  setLastSnapshotResult: Dispatch<SetStateAction<ExportSnapshotResult | ImportSnapshotResult | null>>;
  setSnapshotStatus: Dispatch<SetStateAction<SnapshotStatus | null>>;
  setSnapshotFilePath: Dispatch<SetStateAction<string>>;
  setLastExportPath: Dispatch<SetStateAction<string | null>>;
  exportScopeMode: 'full' | 'scoped';
  exportScopeCategories: SnapshotExportCategory[];
  snapshotBusy: boolean;
  snapshotFilePath: string;
}

export function getImportedTotal(result: ImportSnapshotResult): number {
  return result.entities_created + result.entities_updated;
}
