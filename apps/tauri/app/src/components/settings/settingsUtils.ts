import type { QueryClient } from '@tanstack/react-query';
import { invalidateDataImportQueries } from '@/lib/query/queryKeys';
export interface SnapshotPreview {
  /** The file name of the selected ZIP archive (null if none selected). */
  fileName: string | null;
  /** The full file path of the selected ZIP archive. */
  filePath: string | null;
}

export function errorLevelPillClass(level: string): string {
  switch (level) {
    case 'debug':
      return 'bg-surface-3 text-text-muted';
    case 'info':
      return 'bg-accent/15 text-accent';
    case 'warn':
      return 'chip-warning';
    default:
      return 'chip-danger';
  }
}

export function levelForChangelogOperation(operation: string): string {
  if (operation === 'feedback') return 'warn';
  if (operation === 'delete' || operation === 'cancel' || operation === 'permanent_delete') return 'warn';
  return 'info';
}

export function invalidateAllAfterSnapshotImport(qc: QueryClient) {
  invalidateDataImportQueries(qc);
}

export function extractSnapshotFileName(filePath: string): string | null {
  if (!filePath) return null;
  const parts = filePath.replace(/\\/g, '/').split('/');
  return parts[parts.length - 1] || null;
}

export function buildSnapshotPreview(filePath: string): SnapshotPreview {
  return {
    fileName: extractSnapshotFileName(filePath),
    filePath: filePath || null,
  };
}
