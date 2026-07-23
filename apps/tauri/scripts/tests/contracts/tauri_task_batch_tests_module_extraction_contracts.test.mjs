import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const legacyPath = path.join(
  repoRoot,
  'app/src-tauri/src/commands/tasks/batch/tests.rs',
);
const moduleDir = path.join(
  repoRoot,
  'app/src-tauri/src/commands/tasks/batch/tests',
);

function read(relativePath) {
  return fs.readFileSync(path.join(moduleDir, relativePath), 'utf8');
}

const expectedTestNames = [
  'batch_cancel_empty_selection_returns_no_tokens',
  'batch_cancel_enqueues_spawned_successor_children',
  'batch_cancel_returns_distinct_tokens_and_enqueues_plain_task_rows',
  'batch_cancel_returns_undo_token_per_cancelled_task',
  'batch_cancel_row_level_undo_leaves_sibling_cancelled',
  'batch_cancel_with_series_returns_tokens_for_all_tombstones',
  'batch_complete_enqueues_focus_rewire_aggregates',
  'batch_complete_enqueues_spawned_successor_children_and_spotlight_ids',
  'batch_complete_partial_undo_restores_undone_task_and_keeps_sibling_successor',
  'batch_complete_returns_distinct_tokens_and_enqueues_plain_task_rows',
  'batch_complete_tasks_with_conn_all_skipped_returns_empty_result',
  'batch_complete_tasks_with_conn_completes_open_and_skips_terminal',
  'batch_complete_tasks_with_conn_deduplicates_input_ids',
  'batch_complete_tasks_with_conn_rejects_empty_input',
  'batch_defer_tasks_with_conn_defers_open_tasks_and_skips_terminal_tasks',
  'batch_defer_tasks_with_conn_rejects_invalid_structured_reason',
  'batch_defer_tasks_with_conn_rejects_malformed_until_date',
  'batch_defer_tasks_with_conn_rejects_stale_version_without_side_effects',
  'batch_defer_tasks_with_conn_shifts_pending_reminder_and_enqueues_outbox',
  'batch_move_tasks_with_conn_moves_open_tasks_and_skips_cancelled_and_missing',
  'batch_move_tasks_with_conn_rejects_empty_task_ids',
  'batch_move_tasks_with_conn_rejects_non_uuid_target_list_id',
  'batch_move_tasks_with_conn_requires_target_list_id',
  'batch_reopen_tasks_with_conn_enqueues_reopened_reminder_outbox',
  'batch_reopen_tasks_with_conn_rejects_empty_input',
  'batch_reopen_tasks_with_conn_reopens_terminal_and_skips_open',
  'validate_batch_task_ids_accepts_boundary_limit',
  'validate_batch_task_ids_deduplicates_first_seen_ids',
  'validate_batch_task_ids_rejects_empty_input',
  'validate_batch_task_ids_rejects_non_uuid_ids',
  'validate_batch_task_ids_rejects_too_many_ids',
].sort();

function testNamesIn(relativePath) {
  return [...read(relativePath).matchAll(/^fn\s+([a-zA-Z0-9_]+)\s*\(/gm)].map((match) => match[1]);
}

test('Tauri task batch command tests are split by command domain', () => {
  assert.ok(
    !fs.existsSync(legacyPath),
    'batch command tests should use tests/mod.rs, not the old 1300+ line tests.rs hotspot',
  );

  const rootSource = read('mod.rs');
  assert.ok(
    rootSource.split('\n').length <= 80,
    'batch/tests/mod.rs should stay a small test facade',
  );

  for (const moduleName of ['cancel', 'complete', 'move_defer', 'reopen', 'support', 'validation']) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `batch/tests/mod.rs should register ${moduleName}.rs`,
    );
    assert.ok(
      fs.existsSync(path.join(moduleDir, `${moduleName}.rs`)),
      `${moduleName}.rs should exist under app/src-tauri/src/commands/tasks/batch/tests/`,
    );
  }

  assert.match(read('support.rs'), /\npub\(super\) fn uid\b/);
  assert.match(read('support.rs'), /\npub\(super\) fn seed_task\b/);
  assert.match(read('validation.rs'), /\bfn\s+validate_batch_task_ids_rejects_empty_input\b/);
  assert.match(read('move_defer.rs'), /\bfn\s+batch_move_tasks_with_conn_moves_open_tasks_and_skips_cancelled_and_missing\b/);
  assert.match(read('move_defer.rs'), /\bfn\s+batch_defer_tasks_with_conn_rejects_stale_version_without_side_effects\b/);
  assert.match(read('cancel.rs'), /\bfn\s+batch_cancel_returns_undo_token_per_cancelled_task\b/);
  assert.match(read('complete.rs'), /\bfn\s+batch_complete_enqueues_focus_rewire_aggregates\b/);
  assert.match(read('reopen.rs'), /\bfn\s+batch_reopen_tasks_with_conn_reopens_terminal_and_skips_open\b/);

  const actualTestNames = ['cancel.rs', 'complete.rs', 'move_defer.rs', 'reopen.rs', 'validation.rs']
    .flatMap(testNamesIn)
    .sort();
  assert.deepEqual(
    actualTestNames,
    expectedTestNames,
    'split batch test modules should preserve the complete migrated test-name set',
  );
});
