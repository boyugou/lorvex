import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

test('sync_runtime delegates status snapshot loading to a dedicated status module', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime.rs'),
    'utf8',
  );
  const statusSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime/status.rs'),
    'utf8',
  );

  assert.match(rootSource, rustModuleDeclarationPattern('status'));
  assert.match(
    rootSource,
    /^pub use status::\{get_sync_status, SyncStatus\};$/m,
    'sync_runtime root should re-export status IPC surface from status.rs',
  );
  assert.match(
    rootSource,
    /^#\[cfg\(test\)\]\s*pub\(crate\) use status::load_sync_status_from_conn;$/m,
    'sync_runtime root should expose load_sync_status_from_conn only for tests',
  );
  assert.doesNotMatch(
    rootSource,
    /\n#\[tauri::command\]\npub fn get_sync_status\(|\npub\(crate\) fn load_sync_status_from_conn\(|\npub struct SyncStatus \{/,
    'sync_runtime root should no longer inline sync status logic after extraction',
  );

  assert.match(statusSource, /\n#\[tauri::command\]\npub fn get_sync_status\(/);
  assert.match(statusSource, /\npub\(crate\) fn load_sync_status_from_conn\(/);
  assert.match(statusSource, /\npub type SyncStatus = lorvex_store::SyncStatusSnapshot;/);
  assert.doesNotMatch(statusSource, /\npub struct SyncStatus \{/);
});
