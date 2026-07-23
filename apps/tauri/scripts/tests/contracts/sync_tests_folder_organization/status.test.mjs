import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';

test('sync status tests are organized as core, loading, and timestamp-focused modules', () => {
  const syncTestsDir = path.join(repoRoot, 'app/src-tauri/src/commands/tests/sync');
  const statusDir = path.join(syncTestsDir, 'status');
  const statusRoot = fs.readFileSync(path.join(statusDir, 'mod.rs'), 'utf8');
  const statusCoreHelpersSource = fs.readFileSync(path.join(statusDir, 'core_helpers.rs'), 'utf8');
  const statusCoreEventStateSource = fs.readFileSync(path.join(statusDir, 'core_event_state.rs'), 'utf8');
  const statusCoreDeletionsSource = fs.readFileSync(path.join(statusDir, 'core_deletions.rs'), 'utf8');
  const statusLoadingCursorsSource = fs.readFileSync(path.join(statusDir, 'loading_cursors.rs'), 'utf8');
  const statusLoadingLookbackSource = fs.readFileSync(path.join(statusDir, 'loading_lookback.rs'), 'utf8');
  const statusLoadingRetentionSource = fs.readFileSync(path.join(statusDir, 'loading_retention.rs'), 'utf8');
  const statusLoadingTimestampsSource = fs.readFileSync(path.join(statusDir, 'loading_timestamps.rs'), 'utf8');
  const statusTimestampsSource = fs.readFileSync(path.join(statusDir, 'timestamps.rs'), 'utf8');

  for (const moduleName of [
    'core_deletions',
    'core_event_state',
    'core_helpers',
    'loading_cursors',
    'loading_ical_subscriptions',
    'loading_lookback',
    'loading_pending_inbox',
    'loading_retention',
    'loading_timestamps',
    'timestamps',
  ]) {
    assert.match(
      statusRoot,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `status/mod.rs should register ${moduleName}`,
    );
  }
  assert.equal(
    fs.existsSync(path.join(syncTestsDir, 'status.rs')),
    false,
    'commands/tests/sync/status.rs should be replaced by a status/ folder tree',
  );
  assert.equal(
    fs.existsSync(path.join(statusDir, 'core.rs')),
    false,
    'commands/tests/sync/status/core.rs should be replaced by a status/core/ folder tree',
  );

  for (const testName of [
    'preference_value_to_storage_preserves_string_and_json_values',
    'with_immediate_transaction_rolls_back_on_error',
  ]) {
    assert.match(
      statusCoreHelpersSource,
      new RegExp(`fn ${testName}\\(`),
      `status/core/helpers.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'mark_sync_retry_keeps_original_created_at',
    'mark_outbox_entries_synced_is_idempotent_and_clears_last_error',
  ]) {
    assert.match(
      statusCoreEventStateSource,
      new RegExp(`fn ${testName}\\(`),
      `status/core/event_state.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'mark_task_cancelled_marks_status_cancelled_without_removing_row',
    'hard_delete_task_lww_removes_task_row',
  ]) {
    assert.match(
      statusCoreDeletionsSource,
      new RegExp(`fn ${testName}\\(`),
      `status/core/deletions.rs should cover ${testName}`,
    );
  }

  assert.equal(
    fs.existsSync(path.join(statusDir, 'loading.rs')),
    false,
    'commands/tests/sync/status/loading.rs should be replaced by a status/loading/ folder tree',
  );
  for (const testName of [
    'load_sync_status_from_conn_surfaces_filesystem_bridge_cursor_state',
    'load_sync_status_from_conn_flags_empty_filesystem_bridge_cursor_device_id_as_malformed',
  ]) {
    assert.match(
      statusLoadingCursorsSource,
      new RegExp(`fn ${testName}\\(`),
      `status/loading/cursors.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'load_sync_status_from_conn_surfaces_lookback_known_id_skip_metric',
    'load_sync_status_from_conn_flags_malformed_lookback_known_id_skip_timestamp',
  ]) {
    assert.match(
      statusLoadingLookbackSource,
      new RegExp(`fn ${testName}\\(`),
      `status/loading/lookback.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'load_sync_status_from_conn_surfaces_tombstone_and_conflict_retention_state',
    'load_sync_status_from_conn_uses_valid_retention_timestamps_even_when_bad_rows_exist',
  ]) {
    assert.match(
      statusLoadingRetentionSource,
      new RegExp(`fn ${testName}\\(`),
      `status/loading/retention.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'load_sync_status_from_conn_flags_malformed_last_sync_timestamps',
    'load_sync_status_from_conn_trims_valid_timestamp_state',
  ]) {
    assert.match(
      statusLoadingTimestampsSource,
      new RegExp(`fn ${testName}\\(`),
      `status/loading/timestamps.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'sync_checkpoints_survives_offline_online_transition_without_timestamp_regression',
    'upsert_sync_checkpoint_timestamp_if_newer_ignores_invalid_candidate_when_existing_is_valid',
  ]) {
    assert.match(
      statusTimestampsSource,
      new RegExp(`fn ${testName}\\(`),
      `status/timestamps.rs should cover ${testName}`,
    );
  }
});
