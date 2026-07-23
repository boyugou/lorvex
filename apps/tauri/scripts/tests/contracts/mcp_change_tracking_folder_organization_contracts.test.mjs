import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('server_change_tracking is organized as a folder-backed subsystem with focused actor, snapshot, sync-checkpoint, and logging modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/runtime/change_tracking/mod.rs'),
    'utf8',
  );
  const hlcSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/runtime/change_tracking/hlc.rs'),
    'utf8',
  );
  const logChangeSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/runtime/change_tracking/log_change.rs'),
    'utf8',
  );
  const snapshotSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/runtime/change_tracking/snapshot.rs'),
    'utf8',
  );
  const moduleSource = readRustSources('mcp-server/src/runtime/change_tracking');

  for (const moduleName of ['hlc', 'log_change', 'outbox', 'relations', 'retention', 'snapshot']) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.match(rootSource, /^pub\(crate\) use hlc::\{generate_hlc_version, with_hlc_session\};$/m);
  assert.match(
    rootSource,
    /^pub\(crate\) use log_change::\{log_change, write_preview_audit_entry, LogChangeParams\};$/m,
  );
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) struct LogChangeParams \{|\npub\(crate\) fn log_change\(|\npub\(crate\) fn get_sync_checkpoint_value\(/,
    'server_change_tracking root should keep heavyweight change logging in focused modules',
  );

  assert.match(rootSource, /pub\(crate\) fn resolve_ai_actor_name\(/);
  assert.match(rootSource, /pub\(crate\) fn get_or_create_sync_device_id\(/);
  assert.match(rootSource, /pub\(super\) fn dedupe_entity_ids\(/);
  assert.match(rootSource, /pub\(super\) fn is_delete_sync_operation\(/);
  assert.match(hlcSource, /pub\(crate\) fn generate_hlc_version\(/);
  assert.match(hlcSource, /pub\(crate\) fn with_hlc_session</);
  assert.match(logChangeSource, /pub\(crate\) struct LogChangeParams \{/);
  assert.match(logChangeSource, /pub\(crate\) fn log_change\(/);
  assert.match(logChangeSource, /pub\(crate\) fn write_preview_audit_entry\(/);
  assert.match(snapshotSource, /pub\(super\) fn read_current_entity_snapshot\(/);
  assert.doesNotMatch(moduleSource, /pub\(crate\) fn get_sync_checkpoint_value\(/);
});
