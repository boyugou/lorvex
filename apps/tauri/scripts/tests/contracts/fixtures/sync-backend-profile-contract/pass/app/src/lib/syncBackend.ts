export const SYNC_BACKEND_FILESYSTEM_BRIDGE = 'filesystem_bridge' as const;
export const SYNC_BACKEND_REMOTE_PROVIDER = 'remote_provider' as const;

export type SyncBackendKind =
  | typeof SYNC_BACKEND_FILESYSTEM_BRIDGE
  | typeof SYNC_BACKEND_REMOTE_PROVIDER;

export interface SyncBackendConfigs {
  filesystem_bridge: { rootPath: string };
  remote_provider: {};
}

export interface SyncBackendSupportContext {
  availableBackendKinds: readonly SyncBackendKind[];
  supportedSyncBackendKinds: readonly SyncBackendKind[];
}

export interface SyncBackendDescriptor {
  kind: SyncBackendKind;
  configEditorKind: 'none' | 'filesystem_root_path';
}

export function getDefaultSyncBackendKind(
  options: SyncBackendSupportContext,
): SyncBackendKind {
  return options.availableBackendKinds.includes(SYNC_BACKEND_REMOTE_PROVIDER)
    ? SYNC_BACKEND_REMOTE_PROVIDER
    : SYNC_BACKEND_FILESYSTEM_BRIDGE;
}

export function listAvailableSyncBackends(
  options: SyncBackendSupportContext,
): SyncBackendKind[] {
  return options.availableBackendKinds.slice();
}

export function getSyncBackendSupportContext(runtimeProfile: SyncBackendSupportContext): SyncBackendSupportContext {
  return {
    availableBackendKinds: runtimeProfile.supportedSyncBackendKinds,
    supportedSyncBackendKinds: runtimeProfile.supportedSyncBackendKinds,
  };
}

export function getSyncBackendDescriptor(backendKind: SyncBackendKind): SyncBackendDescriptor {
  return {
    kind: backendKind,
    configEditorKind: backendKind === SYNC_BACKEND_FILESYSTEM_BRIDGE ? 'filesystem_root_path' : 'none',
  };
}

export function resolveSyncBackend(options: {
  requestedBackendKindRaw: string;
  availableBackendKinds: readonly SyncBackendKind[];
}): { effectiveBackendKind: SyncBackendKind } {
  if (
    options.requestedBackendKindRaw.trim() === SYNC_BACKEND_REMOTE_PROVIDER
    && options.availableBackendKinds.includes(SYNC_BACKEND_REMOTE_PROVIDER)
  ) {
    return { effectiveBackendKind: SYNC_BACKEND_REMOTE_PROVIDER };
  }
  return { effectiveBackendKind: SYNC_BACKEND_FILESYSTEM_BRIDGE };
}

export function buildSyncBackendConfig(options: {
  backendKind: SyncBackendKind;
  backendConfigs: SyncBackendConfigs;
}) {
  return {
    kind: options.backendKind,
    config: options.backendConfigs[options.backendKind],
  };
}
