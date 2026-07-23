import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

test('sync_runtime apply is organized as a folder-backed subsystem with focused ordering matching and remote modules', () => {
  const applyRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime/apply/mod.rs'),
    'utf8',
  );
  const orderingSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime/apply/ordering.rs'),
    'utf8',
  );
  const matchingSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime/apply/matching.rs'),
    'utf8',
  );
  const remoteSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime/apply/remote.rs'),
    'utf8',
  );
  const remoteWrappersSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime/apply/remote_wrappers.rs'),
    'utf8',
  );
  const syncCheckpointSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime/apply/sync_checkpoint.rs'),
    'utf8',
  );

  for (const moduleName of ['matching', 'ordering', 'remote', 'sync_checkpoint']) {
    assert.match(
      applyRootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `apply root should register ${moduleName}.rs`,
    );
  }

  assert.ok(
    hasRustUseReexport(applyRootSource, {
      modulePath: 'matching',
      symbols: 'incoming_records_match_for_file_idempotency',
      visibility: 'pub(crate)',
    }),
    'apply root should re-export matching helpers from matching.rs',
  );
  assert.ok(
    hasRustUseReexport(applyRootSource, {
      modulePath: 'ordering',
      symbols: ['compare_sync_versions', 'compare_sync_versions_with_outbox_id'],
      visibility: 'pub(crate)',
    }),
    'apply root should re-export runtime ordering helpers from ordering.rs',
  );
  assert.ok(
    hasRustUseReexport(applyRootSource, {
      modulePath: 'ordering',
      symbols: ['latest_entity_sync_version', 'sync_entity_apply_priority'],
      visibility: 'pub(crate)',
    }),
    'apply root should keep test-only ordering helpers reachable behind cfg(test)',
  );
  // The renderer-facing `apply_remote_sync_envelopes` `#[tauri::command]`
  // was deleted intentionally — see remote/wrappers.rs comment block — so
  // the IPC re-export is no longer asserted here.
  assert.ok(
    hasRustUseReexport(applyRootSource, {
      modulePath: 'remote',
      symbols: 'apply_remote_sync_envelopes_with_filesystem_bridge_cursor',
      visibility: 'pub(crate)',
    }),
    'apply root should re-export the runtime transactional apply helper from remote.rs',
  );
  assert.ok(
    hasRustUseReexport(applyRootSource, {
      modulePath: 'remote',
      symbols: 'apply_remote_sync_envelopes_internal',
      visibility: 'pub(crate)',
    }),
    'apply root should keep test-only apply helper access reachable behind cfg(test)',
  );
  assert.ok(
    hasRustUseReexport(applyRootSource, {
      modulePath: 'sync_checkpoint',
      symbols: 'upsert_sync_checkpoint_timestamp_if_newer',
      visibility: 'pub(crate)',
    }),
    'apply root should re-export sync-checkpoint helpers from sync_checkpoint.rs',
  );
  assert.doesNotMatch(
    applyRootSource,
    /\npub\(crate\) fn compare_sync_versions\(|\nfn sync_payloads_match_for_file_idempotency\(|\npub\(crate\) fn apply_remote_sync_envelopes_with_filesystem_bridge_cursor\(|\n#\[tauri::command\]\npub fn apply_remote_sync_envelopes\(/,
    'apply root should stay a composition layer after folder extraction',
  );

  assert.match(orderingSource, /\npub\(crate\) fn compare_sync_versions\(/);
  assert.match(orderingSource, /\npub\(crate\) fn latest_entity_sync_version\(/);
  assert.match(matchingSource, /\npub\(crate\) fn incoming_records_match_for_file_idempotency\(/);
  assert.match(matchingSource, /\npub\(crate\) fn is_supported_incoming_record\(/);
  assert.match(syncCheckpointSource, /\npub\(crate\) fn upsert_sync_checkpoint_timestamp_if_newer\(/);
  assert.match(remoteSource, /pub\(crate\) use super::remote_wrappers::\{/m);
  assert.match(remoteWrappersSource, /\npub\(crate\) fn apply_remote_sync_envelopes_with_filesystem_bridge_cursor\(/);
  // The renderer-facing IPC was deleted; assert the comment marker stays in
  // place so re-introducing it accidentally still trips this contract.
  assert.match(
    remoteWrappersSource,
    /the renderer-facing `apply_remote_sync_envelopes`[\s\S]*`#\[tauri::command\]` was deleted/,
    'remote_wrappers.rs should keep the deletion rationale for the IPC entrypoint',
  );
});
