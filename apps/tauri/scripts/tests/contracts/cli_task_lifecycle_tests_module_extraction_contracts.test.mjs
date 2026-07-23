import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const legacyTestsPath = path.join(repoRoot, 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/tests.rs');
const testsDir = path.join(repoRoot, 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/tests');
const modPath = path.join(testsDir, 'mod.rs');

function read(relativePath) {
  return fs.readFileSync(path.join(testsDir, relativePath), 'utf8');
}

test('CLI task lifecycle tests are organized by lifecycle domain', () => {
  assert.ok(!fs.existsSync(legacyTestsPath), 'task_lifecycle/tests.rs should be replaced by tests/');
  assert.ok(fs.existsSync(modPath), 'task_lifecycle/tests/mod.rs should register focused test modules');

  const modSource = fs.readFileSync(modPath, 'utf8');
  for (const moduleName of [
    'audit_trail',
    'deferral',
    'lifecycle_actions',
    'support',
    'trash_delete',
    'update_edges',
    'update_fields',
  ]) {
    assert.match(
      modSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `tests/mod.rs should register ${moduleName}.rs`,
    );
  }

  const supportSource = read('support.rs');
  // Post-#3285 typed-ID migration: re-exports `seed_task` plus the
  // `tid` helper that wraps `&str` literals into `&TaskId` at test
  // call sites. The contract just pins that `seed_task` is reachable
  // from the support module — the brace-list / single-import shape is
  // a stylistic detail rustfmt + the agent migration owns.
  assert.match(supportSource, /pub\(super\) use crate::commands::shared::test_support::(?:seed_task|\{[^}]*\bseed_task\b[^}]*\});/);
  assert.match(supportSource, /pub\(super\) use lorvex_domain::naming::\{/);

  const updateFieldsSource = read('update_fields.rs');
  assert.match(updateFieldsSource, /\bfn\s+update_task_with_conn_updates_core_fields_and_syncs\b/);
  assert.match(updateFieldsSource, /\bfn\s+update_task_with_conn_clears_nullable_fields\b/);

  const updateEdgesSource = read('update_edges.rs');
  assert.match(updateEdgesSource, /\bfn\s+update_task_with_conn_patches_tags_and_syncs_edges\b/);
  assert.match(updateEdgesSource, /\bfn\s+update_task_with_conn_rejects_dependency_cycles\b/);

  const lifecycleActionsSource = read('lifecycle_actions.rs');
  assert.match(lifecycleActionsSource, /\bfn\s+complete_task_with_conn_updates_task_and_outbox\b/);
  assert.match(lifecycleActionsSource, /\bfn\s+defer_task_in_tx_shifts_pending_reminder_and_enqueues_reminder_outbox\b/);

  const trashDeleteSource = read('trash_delete.rs');
  assert.match(trashDeleteSource, /\bfn\s+trash_lifecycle_archives_restores_and_gates_permanent_delete\b/);
  assert.match(trashDeleteSource, /\bfn\s+permanent_delete_task_with_conn_deletes_archived_task_and_syncs_children\b/);

  const deferralSource = read('deferral.rs');
  assert.match(deferralSource, /\bfn\s+defer_task_with_conn_rejects_invalid_structured_reason\b/);
  assert.match(deferralSource, /\bfn\s+defer_task_with_conn_rejects_non_positive_days\b/);

  const auditTrailSource = read('audit_trail.rs');
  assert.match(auditTrailSource, /\bfn\s+cli_audit_trail_threads_before_after_and_cascade_tombstones\b/);
});
