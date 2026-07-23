export type SyncBackendConfig =
  | { kind: 'filesystem_bridge'; config: { rootPath: string } }
  | { kind: 'remote_provider'; config: {} };

export interface RunSyncBackendNowOptions {
  backend: SyncBackendConfig;
  maxEvents: number;
}

export interface RunSyncBackendNowResult {
  backendKind: 'filesystem_bridge' | 'remote_provider';
  backendResult: unknown | null;
  summary: {
    pushed: number;
    pulledRemoteEvents: number;
    applied: number;
    pushErrors: number;
    pullLimitHit: boolean;
  };
}

export async function runSyncBackendNow(
  _options: RunSyncBackendNowOptions,
): Promise<RunSyncBackendNowResult> {
  return {
    backendKind: 'filesystem_bridge',
    backendResult: null,
    summary: { pushed: 0, pulledRemoteEvents: 0, applied: 0, pushErrors: 0, pullLimitHit: false },
  };
}
