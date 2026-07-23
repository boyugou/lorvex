import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const legacyPath = path.join(repoRoot, 'lorvex-workflow/src/lifecycle/tests.rs');
const moduleDir = path.join(repoRoot, 'lorvex-workflow/src/lifecycle/tests');

function read(relativePath) {
  return fs.readFileSync(path.join(moduleDir, relativePath), 'utf8');
}

const expectedTestNames = [
  'append_to_task_body_on_empty_body',
  'append_to_task_body_on_existing_body',
  'append_to_task_body_on_null_body',
  'append_to_task_body_rejects_combined_over_cap',
  'append_to_task_body_rejects_stale_version',
  'append_to_task_body_updates_timestamp_and_version',
  'apply_cancel_transition_panics_in_autocommit_in_debug_builds',
  'apply_completion_transition_panics_in_autocommit_in_debug_builds',
  'apply_lifecycle_transition_panics_in_autocommit_in_debug_builds',
  'apply_reopen_transition_cancels_spawned_successor_and_collects_side_effects',
  'apply_reopen_transition_panics_in_autocommit_in_debug_builds',
  'cadence_uses_canonical_occurrence_date_not_deferred_due_date',
  'cancel_active_reminders_skips_lww_loser_rows',
  'cancel_all_in_recurrence_group_leaves_group_id_intact',
  'cancel_already_cancelled_recurring_task_is_idempotent',
  'cancel_one_recurring_sibling_does_not_affect_others_in_group',
  'cancel_recurring_task_preserves_recurrence_group_id',
  'cancel_series_advances_version_when_clearing_recurrence_fields',
  'cancel_series_surfaces_stale_version_when_peer_advances_first',
  'cancel_series_uses_caller_supplied_hlc_for_recurrence_clear',
  'cancel_skip_spawn_copies_only_pre_transition_active_reminders',
  'cancel_task_rejects_stale_version',
  'cancel_task_removes_from_dependents',
  'cancellation_rejects_completed_task_at_shared_layer',
  'complete_already_completed_returns_not_updated',
  'complete_cancels_active_reminders',
  'complete_task_rejects_stale_version',
  'complete_task_sets_status_and_clears_deferral',
  'completion_rejects_cancelled_task_at_shared_layer',
  'completion_rejects_unparseable_persisted_status_before_mutation',
  'completion_spawn_copies_only_pre_transition_active_reminders',
  'completion_transition_does_not_spawn_when_no_recurrence',
  'completion_transition_propagates_successor_tag_copy_failures',
  'completion_transition_rejects_invalid_now_timestamp',
  'completion_transition_rejects_malformed_timezone_preference',
  'completion_transition_surfaces_timezone_preference_lookup_failures',
  'generic_cancel_transition_copies_only_pre_transition_active_reminders',
  'generic_completion_transition_copies_only_pre_transition_active_reminders',
  'generic_lifecycle_transition_rejects_terminal_to_terminal_status_patch',
  'reopen_already_open_returns_not_updated',
  'reopen_cancelled_recurring_task_preserves_group',
  'reopen_cancelled_task_works',
  'reopen_does_not_cancel_unrelated_same_title_recurring_task',
  'reopen_ignores_same_group_task_without_spawned_from',
  'reopen_leaves_dismissed_reminders_alone',
  'reopen_task_clears_completion_and_deferral_state',
  'reopen_task_rejects_stale_version',
  'reopen_transition_propagates_successor_cancel_failures',
  'reopen_uncancels_reminders_and_clears_delivery_state',
  'spawn_preserves_canonical_occurrence_date_independence',
  'spawn_preserves_planned_date_offset',
  'spawn_recurrence_successor_preserves_historical_focus_blocks',
  'spawn_recurrence_successor_rewires_current_focus_items',
  'spawn_recurrence_successor_rewires_focus_schedule_blocks_for_today_and_later',
  'spawn_skips_exdate_dates',
  'spawn_with_count_decrements',
  'spawn_with_uncapped_task_count_decrements',
  'spawn_with_until_stops_after_bound',
  'spawn_without_planned_date_leaves_null',
  'uncancel_task_reminders_skips_lww_loser_rows',
].sort();

function testNamesIn(relativePath) {
  return [...read(relativePath).matchAll(/^#\[test\]\n(?:#\[[^\n]+\]\n)*fn\s+([a-zA-Z0-9_]+)\s*\(/gm)].map(
    (match) => match[1],
  );
}

test('store shared lifecycle tests are split by behavior domain', () => {
  assert.ok(
    !fs.existsSync(legacyPath),
    'shared lifecycle tests should use tests/mod.rs, not the old 1500+ line tests.rs hotspot',
  );

  const rootSource = read('mod.rs');
  assert.ok(
    rootSource.split('\n').length <= 80,
    'lifecycle/tests/mod.rs should stay a small test facade',
  );

  for (const moduleName of [
    'cancel_series',
    'focus_rewire',
    'primitives',
    'recurrence',
    'reminders',
    'support',
    'transitions',
  ]) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `lifecycle/tests/mod.rs should register ${moduleName}.rs`,
    );
    assert.ok(
      fs.existsSync(path.join(moduleDir, `${moduleName}.rs`)),
      `${moduleName}.rs should exist under lorvex-workflow/src/lifecycle/tests/`,
    );
  }

  assert.match(read('support.rs'), /\npub\(super\) fn run_completion_in_tx\b/);
  assert.match(read('support.rs'), /\npub\(super\) fn seed_status_task\b/);
  assert.match(read('transitions.rs'), /\bfn\s+completion_rejects_cancelled_task_at_shared_layer\b/);
  assert.match(read('recurrence.rs'), /\bfn\s+spawn_with_count_decrements\b/);
  assert.match(read('reminders.rs'), /\bfn\s+generic_cancel_transition_copies_only_pre_transition_active_reminders\b/);
  assert.match(read('focus_rewire.rs'), /\bfn\s+spawn_recurrence_successor_rewires_current_focus_items\b/);
  assert.match(read('cancel_series.rs'), /\bfn\s+cancel_series_surfaces_stale_version_when_peer_advances_first\b/);
  assert.match(read('transitions.rs'), /\bfn\s+apply_lifecycle_transition_panics_in_autocommit_in_debug_builds\b/);
  assert.match(read('primitives.rs'), /\bfn\s+append_to_task_body_on_empty_body\b/);

  const actualTestNames = [
    'cancel_series.rs',
    'focus_rewire.rs',
    'primitives.rs',
    'recurrence.rs',
    'reminders.rs',
    'transitions.rs',
  ]
    .flatMap(testNamesIn)
    .sort();
  assert.deepEqual(
    actualTestNames,
    expectedTestNames,
    'split lifecycle test modules should preserve the complete migrated test-name set',
  );
});
