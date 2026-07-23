import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('sync_apply is organized as a folder-backed subsystem instead of a mixed entity hotspot', () => {
  // sync_apply was consolidated into sync_runtime/apply/ as a subtree
  const applyDir = path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime/apply');
  const modSource = fs.readFileSync(path.join(applyDir, 'mod.rs'), 'utf8');
  const applySource = readRustSources('app/src-tauri/src/commands/sync/runtime/apply');

  for (const moduleName of ['matching', 'ordering', 'remote', 'sync_checkpoint']) {
    assert.match(
      modSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `sync_runtime/apply/mod.rs should register ${moduleName}.rs`,
    );
  }

  assert.match(
    modSource,
    /pub(?:\(crate\))? use remote::apply_remote_sync_envelopes_internal;/m,
    'apply/mod.rs should re-export the internal apply entrypoint from remote.rs',
  );
  assert.match(
    modSource,
    /pub(?:\(crate\))? use remote::apply_remote_sync_envelopes_with_filesystem_bridge_cursor;/m,
    'apply/mod.rs should re-export the filesystem-bridge apply entrypoint from remote.rs',
  );
  assert.doesNotMatch(
    modSource,
    /\npub fn apply_remote_sync_envelopes\(/,
    'apply/mod.rs should not inline the apply function body',
  );

  assert.match(applySource, /fn apply_remote_sync_envelopes_internal\(/);
  assert.match(applySource, /fn compare_sync_versions\(/);
  assert.match(applySource, /fn incoming_records_match_for_file_idempotency\(/);
  assert.match(applySource, /fn upsert_sync_checkpoint_timestamp_if_newer\(/);
});
