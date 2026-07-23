import assert from 'node:assert/strict';
import test from 'node:test';

import { readIpcSources, readRustSources } from './shared.mjs';

test('ApplyRemoteSyncResult stays aligned between Rust runtime and TS IPC surfaces', () => {
  const rustSource = readRustSources(
    'app/src-tauri/src/commands/sync/runtime.rs',
    'app/src-tauri/src/commands/sync/runtime',
  );
  const ipcSource = readIpcSources();

  for (const field of [
    'received',
    'processed',
    'applied',
    'skipped_duplicate',
    'skipped_stale',
    'skipped_deferred',
    'skipped_malformed',
    'diagnostics_log_failures',
  ]) {
    assert.match(
      rustSource,
      new RegExp(`pub ${field}: i64`),
      `Rust ApplyRemoteSyncResult should expose ${field}`,
    );
    assert.match(
      ipcSource,
      new RegExp(`${field}: number;`),
      `ipc.ts ApplyRemoteSyncResult should expose ${field}`,
    );
  }
});
