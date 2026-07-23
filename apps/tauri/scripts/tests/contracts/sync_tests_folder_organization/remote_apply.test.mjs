import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';

test('sync remote-apply tests are organized as conflict, entity, and ingest subtrees', () => {
  const syncTestsDir = path.join(repoRoot, 'app/src-tauri/src/commands/tests/sync');
  const remoteApplyDir = path.join(syncTestsDir, 'remote_apply');
  const remoteApplyRoot = fs.readFileSync(path.join(remoteApplyDir, 'mod.rs'), 'utf8');
  const remoteApplyConflictsOrderingSource = fs.readFileSync(path.join(remoteApplyDir, 'conflicts_ordering.rs'), 'utf8');
  const remoteApplyConflictsScenariosDeleteUpdateSource = fs.readFileSync(path.join(remoteApplyDir, 'conflicts_scenario_delete_update.rs'), 'utf8');
  const remoteApplyConflictsScenariosDeterminismSource = fs.readFileSync(path.join(remoteApplyDir, 'conflicts_scenario_determinism.rs'), 'utf8');
  const remoteApplyConflictsScenariosConflictMatrixSource = fs.readFileSync(path.join(remoteApplyDir, 'conflicts_scenario_conflict_matrix.rs'), 'utf8');
  const remoteApplyConflictsStaleSource = fs.readFileSync(path.join(remoteApplyDir, 'conflicts_stale.rs'), 'utf8');
  const remoteApplyEntitiesSource = fs.readFileSync(path.join(remoteApplyDir, 'entities.rs'), 'utf8');
  const remoteApplyIngestSource = fs.readFileSync(path.join(remoteApplyDir, 'ingest.rs'), 'utf8');

  for (const moduleName of [
    'conflicts_ordering',
    'conflicts_scenario_conflict_matrix',
    'conflicts_scenario_delete_update',
    'conflicts_scenario_determinism',
    'conflicts_stale',
  ]) {
    assert.match(remoteApplyRoot, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.match(remoteApplyRoot, /^mod entities;$/m, 'remote_apply/mod.rs should register the entities test module');
  assert.match(remoteApplyRoot, /^mod ingest;$/m, 'remote_apply/mod.rs should register the ingest test module');
  assert.equal(
    fs.existsSync(path.join(syncTestsDir, 'remote_apply.rs')),
    false,
    'commands/tests/sync/remote_apply.rs should be replaced by a remote_apply/ folder tree',
  );
  assert.equal(
    fs.existsSync(path.join(remoteApplyDir, 'conflicts.rs')),
    false,
    'commands/tests/sync/remote_apply/conflicts.rs should be replaced by flat conflicts_* modules',
  );

  for (const testName of [
    'apply_remote_sync_envelopes_applies_depends_on_and_skips_stale_peer',
  ]) {
    assert.match(
      remoteApplyEntitiesSource,
      new RegExp(`fn ${testName}\\(`),
      `remote_apply/entities.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'apply_remote_sync_envelopes_replay_is_idempotent_for_duplicate_event_id',
    'apply_remote_sync_envelopes_skips_malformed_payload_without_rolling_back_batch',
  ]) {
    assert.match(
      remoteApplyIngestSource,
      new RegExp(`fn ${testName}\\(`),
      `remote_apply/ingest.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'apply_remote_sync_envelopes_lww_by_timestamp_for_same_task_field',
    'apply_remote_sync_envelopes_applies_remote_on_timestamp_tie_with_higher_device_id',
  ]) {
    assert.match(
      remoteApplyConflictsOrderingSource,
      new RegExp(`fn ${testName}\\(`),
      `remote_apply/conflicts_ordering.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'apply_remote_sync_envelopes_handles_delete_update_conflicts',
    'apply_remote_sync_envelopes_delete_update_tie_breaks_by_device_id',
  ]) {
    assert.match(
      remoteApplyConflictsScenariosDeleteUpdateSource,
      new RegExp(`fn ${testName}\\(`),
      `remote_apply/conflicts/scenarios/delete_update.rs should cover ${testName}`,
    );
  }
  assert.match(
    remoteApplyConflictsScenariosDeterminismSource,
    /fn apply_remote_sync_envelopes_is_deterministic_across_input_order\(/,
    'remote_apply/conflicts/scenarios/determinism.rs should own whole-batch determinism regressions',
  );
  assert.match(
    remoteApplyConflictsScenariosConflictMatrixSource,
    /fn two_device_conflict_matrix_preserves_deterministic_tie_break_order\(/,
    'remote_apply/conflicts/scenarios/conflict_matrix.rs should own the tie-break conflict matrix regression',
  );
  for (const testName of [
    'apply_remote_sync_envelopes_skips_stale_updates_but_records_event',
    'apply_remote_sync_envelopes_skips_stale_remote_when_local_write_is_newer',
  ]) {
    assert.match(
      remoteApplyConflictsStaleSource,
      new RegExp(`fn ${testName}\\(`),
      `remote_apply/conflicts/stale.rs should cover ${testName}`,
    );
  }
});
