import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const REMOTE_FACADE_PATH = 'app/src-tauri/src/commands/sync/runtime/apply/remote.rs';
const REMOTE_MODULE_DIR = 'app/src-tauri/src/commands/sync/runtime/apply';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('sync runtime remote apply is split into focused modules behind a thin facade', () => {
  const remoteDir = path.join(repoRoot, REMOTE_MODULE_DIR);
  assert.ok(!fs.existsSync(path.join(remoteDir, 'remote')), 'remote apply modules should stay flat remote_* siblings');

  const moduleFiles = fs
    .readdirSync(remoteDir)
    .filter((entry) => entry.endsWith('.rs') && entry.startsWith('remote'))
    .sort();
  assert.deepEqual(
    moduleFiles,
    [
      'remote.rs',
      'remote_core.rs',
      'remote_cursors.rs',
      'remote_diagnostics.rs',
      'remote_events.rs',
      'remote_model.rs',
      'remote_pending.rs',
      'remote_wrappers.rs',
    ],
    'remote apply responsibilities should live in stable focused modules',
  );

  const facade = read(REMOTE_FACADE_PATH);
  const core = read(`${REMOTE_MODULE_DIR}/remote_core.rs`);
  const cursors = read(`${REMOTE_MODULE_DIR}/remote_cursors.rs`);
  const diagnostics = read(`${REMOTE_MODULE_DIR}/remote_diagnostics.rs`);
  const events = read(`${REMOTE_MODULE_DIR}/remote_events.rs`);
  const model = read(`${REMOTE_MODULE_DIR}/remote_model.rs`);
  const pending = read(`${REMOTE_MODULE_DIR}/remote_pending.rs`);
  const wrappers = read(`${REMOTE_MODULE_DIR}/remote_wrappers.rs`);

  assert.ok(
    facade.split('\n').length <= 65,
    'remote.rs should stay a thin facade after module extraction',
  );
  for (const moduleName of [
    'remote_core',
    'remote_events',
    'remote_model',
    'remote_pending',
    'remote_wrappers',
  ]) {
    assert.match(facade, new RegExp(`super::${moduleName}::`, 'm'));
  }
  assert.doesNotMatch(
    facade,
    /\n(?:pub\(crate\)\s+)?(?:async\s+)?fn |\nconst |\nenum |\n#\[test\]|\n#\[tauri::command\]/,
    'remote facade should not retain implementation code',
  );

  assert.match(facade, /pub\(crate\) use super::remote_core::apply_remote_sync_records_with_checkpoint_writer;/);
  assert.ok(
    /pub\(crate\) use super::remote_model::RemoteApplyMode;/.test(facade),
  );
  assert.match(facade, /pub\(crate\) use super::remote_pending::drain_pending_inbox;/);
  assert.match(facade, /pub\(crate\) use super::remote_events::emit_data_changed_for_entity_types;/);
  assert.match(facade, /pub\(crate\) use super::remote_wrappers::\{[\s\S]*apply_remote_sync_envelopes_internal[\s\S]*apply_remote_sync_envelopes_with_filesystem_bridge_cursor[\s\S]*\};/);

  assert.match(core, /\npub\(crate\) (?:const )?fn apply_remote_sync_records_with_checkpoint_writer</);
  assert.match(core, /\n(?:const )?fn invalid_incoming_record_error\(/);
  assert.match(core, /\n(?:const )?fn strict_apply_error\(/);
  for (const dependency of [
    'record_sync_apply_cycle_best_effort',
    'persist_sync_apply_runtime_warning',
    'record_device_cursors_from_applied_records',
    'drain_pending_inbox',
    'emit_data_changed_for_entity_types',
    'RemoteApplyMode',
    'apply_envelope',
  ]) {
    assert.match(core, new RegExp(`\\b${dependency}\\b`), `core should use ${dependency}`);
  }
  assert.doesNotMatch(
    core,
    /\n(?:const )?fn emit_data_changed_for_entity_types\(|\n(?:const )?fn record_device_cursors_from_applied_records\(|\n(?:const )?fn record_sync_apply_cycle\(/,
    'core should orchestrate helpers without owning their implementations',
  );

  assert.match(diagnostics, /\npub\(super\) (?:const )?fn duration_ms_saturating\(/);
  assert.match(diagnostics, /\npub\(super\) (?:const )?fn record_sync_apply_cycle_best_effort\(/);
  assert.match(diagnostics, /\npub\(super\) (?:const )?fn persist_sync_apply_runtime_warning\(/);
  assert.doesNotMatch(
    diagnostics,
    /apply_remote_sync_records_with_checkpoint_writer|emit_data_changed_for_entity_types/,
  );

  assert.match(events, /\n(?:const )?fn entity_type_to_bus\(/);
  assert.match(events, /\npub\(crate\) (?:const )?fn emit_data_changed_for_entity_types\(/);
  assert.doesNotMatch(events, /record_device_cursors_from_batch|record_sync_apply_cycle/);

  assert.match(cursors, /\npub\(super\) (?:const )?fn record_device_cursors_from_applied_records\(/);
  assert.doesNotMatch(
    cursors,
    /\n(?:pub\(crate\)\s+)?fn apply_remote_sync_records_with_checkpoint_writer|\n(?:pub\(crate\)\s+)?fn emit_data_changed/,
  );

  assert.match(model, /\npub\(crate\) enum RemoteApplyMode \{/);
  assert.doesNotMatch(model, /\n(?:const )?fn /);

  assert.match(pending, /\npub\(crate\) (?:const )?fn drain_pending_inbox\(/);
  assert.doesNotMatch(pending, /apply_remote_sync_records_with_checkpoint_writer|record_device_cursors/);

  assert.match(wrappers, /\npub\(crate\) (?:const )?fn apply_remote_sync_envelopes_with_filesystem_bridge_cursor\(/);
  assert.match(wrappers, /\npub\(crate\) (?:const )?fn apply_remote_sync_envelopes_internal\(/);
  assert.match(
    wrappers,
    /the renderer-facing `apply_remote_sync_envelopes`[\s\S]*`#\[tauri::command\]` was deleted/,
    'wrapper module should keep the deleted IPC rationale next to test-only apply wrappers',
  );
});
