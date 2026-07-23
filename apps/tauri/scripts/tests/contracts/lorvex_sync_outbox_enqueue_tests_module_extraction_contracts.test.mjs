import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const legacyPath = path.join(repoRoot, 'lorvex-sync/src/outbox_enqueue/tests.rs');
const moduleDir = path.join(repoRoot, 'lorvex-sync/src/outbox_enqueue/tests');

function read(relativePath) {
  return fs.readFileSync(path.join(moduleDir, relativePath), 'utf8');
}

const expectedTestNames = [
  'aggregate_with_children_calendar_event_carries_attendees',
  'aggregate_with_children_current_focus_carries_task_ids',
  'aggregate_with_children_daily_review_carries_links',
  'aggregate_with_children_focus_schedule_carries_blocks',
  'aggregate_with_children_missing_row_surfaces_entity_not_found',
  'autocommit_enqueue_rolls_back_parent_when_pending_drain_bookkeeping_fails',
  'calendar_event_link_delete_helpers_return_full_edge_snapshots',
  'coalescing_replaces_first_upsert',
  'enqueue_calendar_subscription_upsert_omits_device_local_retry_state',
  'enqueue_entity_upsert_preserves_forward_compat_shadow_fields_on_local_rewrite',
  'enqueue_payload_delete_creates_tombstone_for_composite_edge',
  'enqueue_payload_delete_preserves_pre_delete_payload_version',
  'enqueue_payload_upsert_stamps_version',
  'enqueue_payload_upsert_surfaces_entity_version_stamp_failures',
  'enqueue_preference_upsert_uses_canonical_json_value_payload',
  'enqueue_upsert_for_list',
  'enqueue_upsert_for_tag',
  'enqueue_upsert_omits_virtual_priority_effective_column',
  'enqueue_upsert_produces_canonical_json',
  'enqueue_upsert_reads_snapshot_and_writes_to_outbox',
  'enqueue_upsert_serializes_sqlite_bool_columns_as_json_bool',
  'entity_not_found_returns_error',
  'entity_type_to_table_covers_all_single_pk_syncable_types',
  'every_registered_aggregate_root_has_a_builder_arm',
  'habit_delete_cascade_helpers_return_full_child_snapshots',
  'hlc_versions_are_monotonically_increasing',
  'local_fk_target_write_drains_pending_inbox_for_matching_child',
  'local_write_with_no_matching_pending_does_not_trigger_drain',
  'stale_delete_rejected_by_outbox_coalesce_does_not_create_tombstone',
  'unknown_entity_type_returns_error',
  'upsert_after_delete_clears_stale_tombstone',
].sort();

function testNamesIn(relativePath) {
  return [
    ...read(relativePath).matchAll(/^#\[test\]\n(?:#\[[^\n]+\]\n)*fn\s+([a-zA-Z0-9_]+)\s*\(/gm),
  ].map((match) => match[1]);
}

test('lorvex-sync outbox enqueue tests are split by behavior domain', () => {
  assert.ok(
    !fs.existsSync(legacyPath),
    'outbox enqueue tests should use tests/mod.rs, not the old 1300+ line tests.rs hotspot',
  );

  const rootSource = read('mod.rs');
  assert.ok(
    rootSource.split('\n').length <= 80,
    'outbox_enqueue/tests/mod.rs should stay a small test facade',
  );

  for (const moduleName of [
    'aggregates',
    'delete_cascade',
    'entity_upserts',
    'payload_writes',
    'pending_drain',
    'support',
  ]) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `outbox_enqueue/tests/mod.rs should register ${moduleName}.rs`,
    );
    assert.ok(
      fs.existsSync(path.join(moduleDir, `${moduleName}.rs`)),
      `${moduleName}.rs should exist under lorvex-sync/src/outbox_enqueue/tests/`,
    );
  }

  assert.match(read('support.rs'), /\npub\(super\) fn setup_hlc\b/);
  assert.match(read('support.rs'), /\npub\(super\) fn insert_task\b/);
  assert.match(read('support.rs'), /\npub\(super\) fn insert_calendar_event\b/);
  assert.match(read('entity_upserts.rs'), /\bfn\s+enqueue_upsert_reads_snapshot_and_writes_to_outbox\b/);
  assert.match(read('payload_writes.rs'), /\bfn\s+enqueue_payload_upsert_stamps_version\b/);
  assert.match(read('aggregates.rs'), /\bfn\s+aggregate_with_children_focus_schedule_carries_blocks\b/);
  assert.match(read('delete_cascade.rs'), /\bfn\s+habit_delete_cascade_helpers_return_full_child_snapshots\b/);
  assert.match(read('pending_drain.rs'), /\bfn\s+local_fk_target_write_drains_pending_inbox_for_matching_child\b/);

  const actualTestNames = [
    'aggregates.rs',
    'delete_cascade.rs',
    'entity_upserts.rs',
    'payload_writes.rs',
    'pending_drain.rs',
  ]
    .flatMap(testNamesIn)
    .sort();
  assert.deepEqual(
    actualTestNames,
    expectedTestNames,
    'split outbox enqueue test modules should preserve the complete migrated test-name set',
  );
});
