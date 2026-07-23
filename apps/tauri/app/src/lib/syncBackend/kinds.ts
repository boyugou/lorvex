export const SYNC_BACKEND_FILESYSTEM_BRIDGE = 'filesystem_bridge' as const;

export type SyncBackendKind = typeof SYNC_BACKEND_FILESYSTEM_BRIDGE;

export const SYNC_BACKEND_PRIORITY: readonly SyncBackendKind[] = [
  SYNC_BACKEND_FILESYSTEM_BRIDGE,
];
