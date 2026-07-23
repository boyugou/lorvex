export type SyncBackendKind = 'filesystem_bridge' | 'remote_provider';

export type SyncBackendConfig =
  | { kind: 'filesystem_bridge'; config: { rootPath: string } }
  | { kind: 'remote_provider'; config: {} };

export interface ResolvedSyncBackend {
  requestedBackendKind: SyncBackendKind;
  effectiveBackendKind: SyncBackendKind;
  shouldNormalizeBackendKind: boolean;
}

export interface RunSyncBackendOptions {
  backend: SyncBackendConfig;
  maxConsecutiveRepulls: number;
  isCancelled: () => boolean;
}

export interface RunSyncBackendResult {
  quickRetryRequested: boolean;
}

interface LocalFileResult {
  pull_limit_hit: boolean;
}

async function executeSyncBackendCore(options: RunSyncBackendOptions): Promise<{ filesystemBridgeResult: LocalFileResult | null }> {
  let result: LocalFileResult = { pull_limit_hit: false };
  let filesystemBridgeResult: LocalFileResult | null = null;
  let consecutiveRepulls = 0;

  while (
    result.pull_limit_hit &&
    consecutiveRepulls < options.maxConsecutiveRepulls &&
    !options.isCancelled()
  ) {
    consecutiveRepulls += 1;
  }

  filesystemBridgeResult = result;

  return {
    filesystemBridgeResult,
  };
}

export function resolveSyncBackend(_raw: string): ResolvedSyncBackend {
  return {
    requestedBackendKind: 'filesystem_bridge',
    effectiveBackendKind: 'filesystem_bridge',
    shouldNormalizeBackendKind: false,
  };
}

export function buildSyncBackendConfig(): SyncBackendConfig {
  return { kind: 'filesystem_bridge', config: { rootPath: '/tmp' } };
}

export function summarizeSyncBackendRun(result: { filesystemBridgeResult: LocalFileResult | null }): { pullLimitHit: boolean } {
  return {
    pullLimitHit: result.filesystemBridgeResult.pull_limit_hit,
  };
}

export async function runSyncBackend(options: RunSyncBackendOptions): Promise<RunSyncBackendResult> {
  const { filesystemBridgeResult } = await executeSyncBackendCore(options);
  return {
    quickRetryRequested: filesystemBridgeResult?.pull_limit_hit ?? false,
  };
}
