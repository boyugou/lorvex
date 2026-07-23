import assert from 'node:assert/strict';
import test from 'node:test';

import type { FilesystemBridgeSyncResult } from '../../../app/src/lib/ipc/sync';
import {
  summarizeSyncBackendRun,
  runSyncBackendNowWithDeps,
  runSyncBackendWithDeps,
} from '../../../app/src/lib/syncBackend/runtime.logic';

function filesystemResult(
  overrides: Partial<FilesystemBridgeSyncResult> = {},
): FilesystemBridgeSyncResult {
  return {
    filesystem_bridge_root_path: '/sync-root',
    attempted_push: 0,
    pushed: 0,
    push_write_errors: 0,
    pulled_files: 0,
    pulled_remote_events: 0,
    pull_parse_errors: 0,
    lookback_known_id_skipped: 0,
    pull_limit_hit: false,
    apply_result: {
      received: 0,
      processed: 0,
      applied: 0,
      skipped_duplicate: 0,
      skipped_stale: 0,
      skipped_deferred: 0,
      skipped_malformed: 0,
      diagnostics_log_failures: 0,
    },
    reseed_paused: false,
    ...overrides,
  };
}

test('runSyncBackendWithDeps repulls filesystem sync until the limit clears and surfaces quick retry', async () => {
  const waits: number[] = [];
  const roots: string[] = [];
  let attempts = 0;
  const deps = {
    runFilesystemBridgeSync: async (rootPath: string) => {
      roots.push(rootPath);
      attempts += 1;
      return attempts < 3
        ? filesystemResult({ pull_limit_hit: true, filesystem_bridge_root_path: rootPath })
        : filesystemResult({ pull_limit_hit: false, filesystem_bridge_root_path: rootPath });
    },
  };

  const result = await runSyncBackendWithDeps({
    backend: { kind: 'filesystem_bridge', config: { rootPath: ' /tmp/bridge ' } },
    maxEvents: 50,
    maxConsecutiveRepulls: 5,
    quickRetryMs: 2_000,
    isCancelled: () => false,
    wait: async (delayMs) => {
      waits.push(delayMs);
    },
  }, deps);

  assert.equal(result.quickRetryRequested, false);
  assert.equal(result.nextDelayOverrideMs, null);
  assert.deepEqual(roots, ['/tmp/bridge', '/tmp/bridge', '/tmp/bridge']);
  assert.deepEqual(waits, [2_000, 2_000]);
});

test('runSyncBackendWithDeps stops after cancellation and skips blank filesystem root paths', async () => {
  let cancelled = false;
  const waits: number[] = [];
  const roots: string[] = [];
  const deps = {
    runFilesystemBridgeSync: async (rootPath: string) => {
      roots.push(rootPath);
      cancelled = true;
      return filesystemResult({ pull_limit_hit: true, filesystem_bridge_root_path: rootPath });
    },
  };

  const cancelledResult = await runSyncBackendWithDeps({
    backend: { kind: 'filesystem_bridge', config: { rootPath: '/tmp/cancel' } },
    maxEvents: 50,
    maxConsecutiveRepulls: 5,
    quickRetryMs: 2_000,
    isCancelled: () => cancelled,
    wait: async (delayMs) => {
      waits.push(delayMs);
    },
  }, deps);
  assert.equal(cancelledResult.quickRetryRequested, true);
  assert.deepEqual(roots, ['/tmp/cancel']);
  assert.deepEqual(waits, []);

  roots.length = 0;
  const blankRootResult = await runSyncBackendWithDeps({
    backend: { kind: 'filesystem_bridge', config: { rootPath: '   ' } },
    maxEvents: 50,
    maxConsecutiveRepulls: 5,
    quickRetryMs: 2_000,
    isCancelled: () => false,
    wait: async () => {},
  }, deps);
  assert.equal(blankRootResult.quickRetryRequested, false);
  assert.equal(blankRootResult.nextDelayOverrideMs, null);
  assert.deepEqual(roots, []);
});

test('runSyncBackendNowWithDeps filesystem summaries include apply counters', async () => {
  const filesystemCalls: string[] = [];
  const deps = {
    runFilesystemBridgeSync: async (rootPath: string) => {
      filesystemCalls.push(rootPath);
      return filesystemResult({
        filesystem_bridge_root_path: rootPath,
        pushed: 7,
        pulled_remote_events: 9,
        push_write_errors: 2,
        pull_limit_hit: true,
        apply_result: {
          received: 10,
          processed: 9,
          applied: 8,
          skipped_duplicate: 0,
          skipped_stale: 1,
          skipped_deferred: 0,
          skipped_malformed: 1,
          diagnostics_log_failures: 2,
        },
      });
    },
  };

  const filesystem = await runSyncBackendNowWithDeps({
    backend: { kind: 'filesystem_bridge', config: { rootPath: '/tmp/manual' } },
    maxEvents: 30,
  }, deps);
  assert.deepEqual(filesystemCalls, ['/tmp/manual']);
  assert.deepEqual(filesystem.summary, {
    pushed: 7,
    pulledRemoteEvents: 9,
    applied: 8,
    pushErrors: 2,
    pullLimitHit: true,
    diagnosticsLogFailures: 2,
  });
});

test('summarizeSyncBackendRun fails closed when no backend result is available', () => {
  assert.deepEqual(
    summarizeSyncBackendRun({
      filesystemBridgeResult: null,
    }),
    {
      pushed: 0,
      pulledRemoteEvents: 0,
      applied: 0,
      pushErrors: 0,
      pullLimitHit: false,
      diagnosticsLogFailures: 0,
    },
  );
});
