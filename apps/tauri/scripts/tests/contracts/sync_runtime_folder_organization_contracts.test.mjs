import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

test('sync_runtime is organized as a folder-backed subsystem instead of a mixed root hotspot', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime.rs'),
    'utf8',
  );
  const applySource = readRustSources(
    'app/src-tauri/src/commands/sync/runtime/apply',
  );
  const queueSource = readRustSources(
    'app/src-tauri/src/commands/sync/runtime/queue',
  );
  const statusSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime/status.rs'),
    'utf8',
  );

  for (const moduleName of ['apply', 'queue', 'status']) {
    assert.match(
      rootSource,
      rustModuleDeclarationPattern(moduleName),
      `sync_runtime root should register ${moduleName}.rs`,
    );
  }

  // The renderer-facing `apply_remote_sync_envelopes` IPC was deleted for
  // security; only the result/record types ride out to the rest of the crate.
  assert.match(
    rootSource,
    /^pub use apply::\{ApplyRemoteSyncResult, IncomingSyncRecord\};$/m,
    'sync_runtime root should re-export apply types from apply.rs',
  );
  assert.match(
    rootSource,
    /^pub use queue::\{[\s\S]*SyncOutboxEntry[\s\S]*\};$/m,
    'sync_runtime root should re-export queue IPC surface from queue.rs',
  );
  assert.match(
    rootSource,
    /^pub use status::\{get_sync_status, SyncStatus\};$/m,
    'sync_runtime root should re-export status IPC surface from status.rs',
  );
  assert.doesNotMatch(
    rootSource,
    /\n#\[tauri::command\]\npub fn get_sync_checkpoint\(|\n#\[tauri::command\]\npub fn get_pending_outbox_entries\(|\n#\[tauri::command\]\npub fn apply_remote_sync_envelopes\(|\npub struct SyncOutboxEntry \{|\npub struct IncomingSyncRecord \{|\npub struct ApplyRemoteSyncResult \{/,
    'sync_runtime root should remain a composition layer after folder extraction',
  );

  assert.match(
    applySource,
    /the renderer-facing `apply_remote_sync_envelopes`[\s\S]*`#\[tauri::command\]` was deleted/,
    'apply subtree should keep the deletion rationale comment for the IPC entrypoint',
  );
  assert.match(applySource, /\npub\(crate\) fn compare_sync_versions\(/);
  assert.match(applySource, /\npub\(crate\) fn incoming_records_match_for_file_idempotency\(/);
  assert.match(applySource, /\npub struct IncomingSyncRecord \{/);
  assert.match(applySource, /\npub struct ApplyRemoteSyncResult \{/);
  assert.match(queueSource, /\npub\(crate\) fn get_or_create_sync_device_id_typed\(/);
  assert.match(queueSource, /\npub struct SyncOutboxEntry \{/);
  assert.match(statusSource, /\npub type SyncStatus = lorvex_store::SyncStatusSnapshot;/);
  assert.doesNotMatch(statusSource, /\npub struct SyncStatus \{/);
});
