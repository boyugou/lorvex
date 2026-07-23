import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('task deferral runtime keeps unit tests in a dedicated tests module', () => {
  const runtimePath = path.join(repoRoot, 'lorvex-workflow/src/task_deferral.rs');
  const testsPath = path.join(repoRoot, 'lorvex-workflow/src/task_deferral/tests.rs');
  const runtimeSource = fs.readFileSync(runtimePath, 'utf8');

  assert.match(
    runtimeSource,
    /#\[cfg\(test\)\]\s*mod tests;/,
    'task_deferral.rs should declare tests as a sibling module',
  );
  assert.doesNotMatch(
    runtimeSource,
    /#\[cfg\(test\)\]\s*mod tests\s*\{/,
    'task_deferral.rs should not keep the task deferral unit tests inline',
  );
  assert.ok(fs.existsSync(testsPath), 'task_deferral/tests.rs should own task deferral unit tests');

  const testsSource = fs.readFileSync(testsPath, 'utf8');
  for (const testName of [
    'defer_with_date_updates_planned_date_and_increments_count',
    'defer_with_new_planned_date_shifts_only_pending_reminders',
    'reset_with_stale_version_is_rejected',
    'restore_with_stale_version_is_rejected',
  ]) {
    assert.match(
      testsSource,
      new RegExp(`\\bfn\\s+${testName}\\b`),
      `task_deferral/tests.rs should own ${testName}`,
    );
  }
});
