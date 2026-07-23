import type { SyncStatus } from '@/lib/ipc/sync';
import { syncBackendUsesFilesystemRootPathEditor } from '@/lib/syncBackend/model';
import type { SyncBackendKind } from '@/lib/syncBackend/kinds';

type SyncSettingsBackendContextSource =
  | 'draft_configured'
  | null;

interface SyncSettingsBackendContext {
  backendKind: SyncBackendKind | null;
  source: SyncSettingsBackendContextSource;
  usesFilesystemRootPathEditor: boolean;
}

export function resolveSyncSettingsBackendContext(options: {
  draftConfiguredBackendKind: SyncBackendKind | null;
}): SyncSettingsBackendContext {
  const backendKind = options.draftConfiguredBackendKind ?? null;
  const source: SyncSettingsBackendContextSource =
    options.draftConfiguredBackendKind !== null
      ? 'draft_configured'
      : null;

  return {
    backendKind,
    source,
    usesFilesystemRootPathEditor: syncBackendUsesFilesystemRootPathEditor(backendKind),
  };
}

export function shouldShowRuntimeBackendDiagnostics(
  syncStatus: SyncStatus | null,
  backendKind: SyncBackendKind,
): boolean {
  return syncStatus?.sync_backend_kind_effective === backendKind;
}
