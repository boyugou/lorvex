import { runFilesystemBridgeSync } from '../ipc/sync';
import {
  type RunSyncBackendNowOptions,
  type RunSyncBackendOptions,
} from './model';
import {
  runSyncBackendNowWithDeps,
  runSyncBackendWithDeps,
} from './runtime.logic';

const SYNC_BACKEND_RUNTIME_DEPS = {
  runFilesystemBridgeSync,
} as const;

export async function runSyncBackend(
  options: RunSyncBackendOptions,
) {
  return runSyncBackendWithDeps(options, SYNC_BACKEND_RUNTIME_DEPS);
}

export async function runSyncBackendNow(
  options: RunSyncBackendNowOptions,
) {
  return runSyncBackendNowWithDeps(options, SYNC_BACKEND_RUNTIME_DEPS);
}
