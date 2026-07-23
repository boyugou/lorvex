import type { FilesystemBridgeSyncResult } from '../ipc/sync';
import {
  type RunSyncBackendNowOptions,
  type RunSyncBackendNowResult,
  type RunSyncBackendOptions,
  type RunSyncBackendResult,
  type SyncBackendRunSummary,
} from './model';

interface ExecuteSyncBackendCoreResult {
  quickRetryRequested: boolean;
  nextDelayOverrideMs: number | null;
  filesystemBridgeResult: FilesystemBridgeSyncResult | null;
}

interface SyncBackendRuntimeDeps {
  runFilesystemBridgeSync: (
    rootPath: string,
    maxEvents?: number,
  ) => Promise<FilesystemBridgeSyncResult>;
}

async function syncWithRepull<T extends { pull_limit_hit: boolean }>(
  run: () => Promise<T>,
  options: RunSyncBackendOptions,
): Promise<T> {
  let consecutiveRepulls = 0;
  let result = await run();
  while (
    result.pull_limit_hit &&
    consecutiveRepulls < options.maxConsecutiveRepulls &&
    !options.isCancelled()
  ) {
    consecutiveRepulls += 1;
    await options.wait(options.quickRetryMs);
    result = await run();
  }
  return result;
}

async function executeSyncBackendCore(
  options: RunSyncBackendOptions,
  deps: SyncBackendRuntimeDeps,
): Promise<ExecuteSyncBackendCoreResult> {
  const rootPath = options.backend.config.rootPath.trim();
  let filesystemBridgeResult: FilesystemBridgeSyncResult | null = null;
  if (rootPath) {
    filesystemBridgeResult = await syncWithRepull(
      () => deps.runFilesystemBridgeSync(rootPath, options.maxEvents),
      options,
    );
  }

  const fsReseedPaused = filesystemBridgeResult?.reseed_paused ?? false;
  return {
    quickRetryRequested: filesystemBridgeResult?.pull_limit_hit ?? false,
    nextDelayOverrideMs: fsReseedPaused ? 10 * 60 * 1000 : null,
    filesystemBridgeResult,
  };
}

export function summarizeSyncBackendRun(
  result: Pick<ExecuteSyncBackendCoreResult, 'filesystemBridgeResult'>,
): SyncBackendRunSummary {
  if (result.filesystemBridgeResult) {
    return {
      pushed: result.filesystemBridgeResult.pushed,
      pulledRemoteEvents: result.filesystemBridgeResult.pulled_remote_events,
      applied: result.filesystemBridgeResult.apply_result.applied,
      pushErrors: result.filesystemBridgeResult.push_write_errors,
      pullLimitHit: result.filesystemBridgeResult.pull_limit_hit,
      diagnosticsLogFailures: result.filesystemBridgeResult.apply_result.diagnostics_log_failures,
    };
  }

  return {
    pushed: 0,
    pulledRemoteEvents: 0,
    applied: 0,
    pushErrors: 0,
    pullLimitHit: false,
    diagnosticsLogFailures: 0,
  };
}

export async function runSyncBackendWithDeps(
  options: RunSyncBackendOptions,
  deps: SyncBackendRuntimeDeps,
): Promise<RunSyncBackendResult> {
  const result = await executeSyncBackendCore(options, deps);
  return {
    quickRetryRequested: result.quickRetryRequested,
    nextDelayOverrideMs: result.nextDelayOverrideMs,
  };
}

export async function runSyncBackendNowWithDeps(
  options: RunSyncBackendNowOptions,
  deps: SyncBackendRuntimeDeps,
): Promise<RunSyncBackendNowResult> {
  const result = await executeSyncBackendCore({
    backend: options.backend,
    maxEvents: options.maxEvents,
    maxConsecutiveRepulls: 0,
    quickRetryMs: 0,
    isCancelled: () => false,
    wait: async () => {},
  }, deps);
  const summary = summarizeSyncBackendRun(result);

  return {
    backendKind: options.backend.kind,
    backendResult: result.filesystemBridgeResult,
    summary,
  };
}
