import type { ExportSnapshotResult, ImportSnapshotResult, SnapshotExportCategory } from '@/lib/ipc/settings';
import type { SnapshotPreview } from '@/components/settings/settingsUtils';
import type { SnapshotStatus } from '../types';

export interface SnapshotPanelProps {
  snapshotBusy: boolean;
  lastSnapshotResult: ExportSnapshotResult | ImportSnapshotResult | null;
  snapshotErrorDetail: string | null;
  snapshotStatus: SnapshotStatus | null;
  lastExportPath: string | null;
  snapshotPreview: SnapshotPreview;
  exportScopeMode: 'full' | 'scoped';
  exportScopeCategories: SnapshotExportCategory[];
  onExportSnapshot: () => Promise<void>;
  onSetExportScopeMode: (value: 'full' | 'scoped') => void;
  onToggleExportScopeCategory: (category: SnapshotExportCategory) => void;
  onLoadSnapshotFile: () => Promise<void>;
  onImportSnapshot: () => Promise<void>;
}
