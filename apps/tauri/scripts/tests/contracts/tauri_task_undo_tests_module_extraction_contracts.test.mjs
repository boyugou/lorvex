import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const legacyPath = path.join(
  repoRoot,
  'app/src-tauri/src/commands/tasks/undo/tests.rs',
);
const moduleDir = path.join(repoRoot, 'app/src-tauri/src/commands/tasks/undo/tests');

function read(relativePath) {
  return fs.readFileSync(path.join(moduleDir, relativePath), 'utf8');
}

const expectedTestNames = [
  'undo_token_serialization_roundtrip',
  'undo_token_defaults_for_missing_fields',
  'expired_token_is_rejected',
  'redo_token_roundtrip_for_complete',
  'redo_token_for_single_cancel_keeps_series_flag_false',
  'redo_token_for_cancel_preserves_series_flag',
  'expired_redo_token_is_rejected',
  'update_undo_does_not_build_redo_token',
  'lifecycle_token_expiry_accepts_rfc3339_offsets',
  'lifecycle_token_expiry_allows_exact_boundary',
  'redo_token_rejects_complete_with_extraneous_cancel_series_field',
  'valid_token_is_accepted',
  'undo_recurrence_completion_publishes_parent_upsert_and_successor_delete',
  'undo_recurrence_completion_restores_focus_plan_rewires',
  'undo_recurrence_completion_after_forward_rows_synced_publishes_reverse_writes',
  'undo_cancel_restores_reminders_and_dependency_edges',
  'malformed_undo_token_json_is_rejected_with_validation_error',
  'apply_single_undo_rejects_task_not_in_expected_post_state',
  'undo_task_lifecycle_batch_rejects_empty_tokens',
].sort();

function testNamesIn(relativePath) {
  return [...read(relativePath).matchAll(/^fn\s+([a-zA-Z0-9_]+)\s*\(/gm)].map((match) => match[1]);
}

test('Tauri task undo command tests are split by behavior domain', () => {
  assert.ok(
    !fs.existsSync(legacyPath),
    'undo command tests should use tests/mod.rs, not the old 800+ line tests.rs hotspot',
  );

  const moduleFiles = fs
    .readdirSync(moduleDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, ['ipc_edges.rs', 'mod.rs', 'recurrence.rs', 'support.rs', 'tokens.rs']);

  const rootSource = read('mod.rs');
  assert.ok(
    rootSource.trimEnd().split('\n').length <= 40,
    'undo/tests/mod.rs should stay a small test facade',
  );
  for (const moduleName of ['ipc_edges', 'recurrence', 'support', 'tokens']) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `undo/tests/mod.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(rootSource, /^use super::\*;/m);
  assert.match(rootSource, /ENTITY_TASK_REMINDER/);
  assert.doesNotMatch(rootSource, /\n#\[test\]|\nfn\s+\w+/, 'undo/tests/mod.rs should not keep test bodies inline');

  const supportSource = read('support.rs');
  assert.match(supportSource, /\npub\(super\) const TEST_VER\b/);
  assert.match(supportSource, /\npub\(super\) const NOW_TS\b/);
  assert.match(supportSource, /\npub\(super\) fn seed_recurrence_undo_fixture\b/);
  assert.match(supportSource, /ENTITY_TASK_REMINDER/);
  assert.doesNotMatch(supportSource, /\n#\[test\]/);

  const tokensSource = read('tokens.rs');
  assert.match(tokensSource, /\bfn undo_token_serialization_roundtrip\b/);
  assert.match(tokensSource, /\bfn redo_token_rejects_complete_with_extraneous_cancel_series_field\b/);
  assert.doesNotMatch(tokensSource, /\bseed_recurrence_undo_fixture\b|\bundo_task_lifecycle_batch_rejects_empty_tokens\b/);

  const recurrenceSource = read('recurrence.rs');
  assert.match(recurrenceSource, /\bfn undo_recurrence_completion_publishes_parent_upsert_and_successor_delete\b/);
  assert.match(recurrenceSource, /\bfn undo_recurrence_completion_restores_focus_plan_rewires\b/);
  assert.match(recurrenceSource, /\bseed_recurrence_undo_fixture\b/);
  assert.doesNotMatch(recurrenceSource, /\bfn undo_token_serialization_roundtrip\b|\bfn undo_task_lifecycle_batch_rejects_empty_tokens\b/);

  const ipcSource = read('ipc_edges.rs');
  assert.match(ipcSource, /\bfn malformed_undo_token_json_is_rejected_with_validation_error\b/);
  assert.match(ipcSource, /\bfn apply_single_undo_rejects_task_not_in_expected_post_state\b/);
  assert.match(ipcSource, /\bfn undo_task_lifecycle_batch_rejects_empty_tokens\b/);
  assert.doesNotMatch(ipcSource, /\bfn redo_token_roundtrip_for_complete\b|\bfn undo_recurrence_completion_restores_focus_plan_rewires\b/);

  const actualTestNames = ['tokens.rs', 'recurrence.rs', 'ipc_edges.rs']
    .flatMap(testNamesIn)
    .sort();
  assert.deepEqual(
    actualTestNames,
    expectedTestNames,
    'split undo test modules should preserve the complete migrated test-name set',
  );
});
