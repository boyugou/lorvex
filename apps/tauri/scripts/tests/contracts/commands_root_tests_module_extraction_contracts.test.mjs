import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('commands root keeps root-specific tests in a dedicated tests module file', () => {
  const commandsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );
  const testsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tests/mod.rs'),
    'utf8',
  );

  assert.match(commandsSource, /^#\[cfg\(test\)\]\s*mod tests;$/m);
  assert.doesNotMatch(
    commandsSource,
    /^#\[cfg\(test\)\]\s*mod tests \{$/m,
    'commands.rs should not inline the root tests module after extraction',
  );
  assert.match(
    testsSource,
    /fn setup_sync_test_conn\(\)[\s\S]*fn insert_task_for_all_tasks_test\(/,
    'commands/tests/mod.rs should keep shared root test scaffolding after subtree extraction',
  );
  for (const moduleName of ['calendar', 'diagnostics', 'task_runtime']) {
    assert.match(
      testsSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `commands/tests/mod.rs should register ${moduleName} after extracting root regressions`,
    );
  }
  assert.doesNotMatch(
    testsSource,
    /^mod widget_snapshot;$/m,
    'Tauri commands tests must not register the retired Apple widget snapshot subsystem',
  );
  assert.doesNotMatch(
    testsSource,
    /fn apply_remote_task_delete_cleans_dependency_refs_with_remote_timestamp\(|fn build_widget_snapshot_/,
    'commands/tests/mod.rs should not keep extracted domain regressions inline',
  );
});
