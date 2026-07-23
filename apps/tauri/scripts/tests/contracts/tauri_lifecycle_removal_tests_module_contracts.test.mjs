import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('task lifecycle removal runtime keeps unit tests in a dedicated tests module', () => {
  // Post-#3303 P1 split: removal.rs became removal/mod.rs alongside
  // cancel/cascade/permanent/purge submodules.
  const runtimePath = path.join(
    repoRoot,
    'app/src-tauri/src/commands/tasks/lifecycle/removal/mod.rs',
  );
  const testsPath = path.join(
    repoRoot,
    'app/src-tauri/src/commands/tasks/lifecycle/removal/tests.rs',
  );
  const runtimeSource = fs.readFileSync(runtimePath, 'utf8');

  assert.match(
    runtimeSource,
    /#\[cfg\(test\)\]\s*mod tests;/,
    'lifecycle/removal.rs should declare tests as a sibling module',
  );
  assert.doesNotMatch(
    runtimeSource,
    /#\[cfg\(test\)\]\s*mod tests\s*\{/,
    'lifecycle/removal.rs should not keep lifecycle removal unit tests inline',
  );
  assert.ok(
    fs.existsSync(testsPath),
    'lifecycle/removal/tests.rs should own lifecycle removal unit tests',
  );

  const testsSource = fs.readFileSync(testsPath, 'utf8');
  for (const testName of [
    'cancel_task_with_conn_cancels_open_task_and_emits_outbox_row',
    'permanent_delete_task_with_conn_emits_child_delete_envelopes_and_tombstones',
    'purge_cancelled_tasks_with_conn_emits_child_delete_envelopes_and_tombstones',
    'permanent_delete_reenqueues_dependent_task_aggregate_after_dependency_cleanup',
  ]) {
    assert.match(
      testsSource,
      new RegExp(`\\bfn\\s+${testName}\\b`),
      `lifecycle/removal/tests.rs should own ${testName}`,
    );
  }
});
