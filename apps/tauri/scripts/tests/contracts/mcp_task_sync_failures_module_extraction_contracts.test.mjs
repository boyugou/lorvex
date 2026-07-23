import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const rootPath = path.join(repoRoot, 'mcp-server/src/server/tests/tasks/sync_failures.rs');
const testsDir = path.join(repoRoot, 'mcp-server/src/server/tests/tasks/sync_failures');

function read(relativePath) {
  return fs.readFileSync(path.join(testsDir, relativePath), 'utf8');
}

test('MCP task sync failure tests are split by rollback domain', () => {
  const rootSource = fs.readFileSync(rootPath, 'utf8');
  assert.ok(
    rootSource.split('\n').length <= 80,
    'tasks/sync_failures.rs should stay a small test-suite facade',
  );
  assert.doesNotMatch(
    rootSource,
    /\n#\[test\]|\nfn assert_is_tool_error\b|\nfn archive_task_for_test\b/,
    'tasks/sync_failures.rs should not keep helper or test implementations inline',
  );

  for (const moduleName of [
    'batch',
    'create_update',
    'lifecycle_actions',
    'permanent_delete',
    'support',
  ]) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `tasks/sync_failures.rs should register ${moduleName}.rs`,
    );
    assert.ok(
      fs.existsSync(path.join(testsDir, `${moduleName}.rs`)),
      `${moduleName}.rs should exist under tasks/sync_failures/`,
    );
  }

  const supportSource = read('support.rs');
  assert.match(supportSource, /\npub\(super\) fn assert_is_tool_error\b/);
  assert.match(supportSource, /\npub\(super\) fn archive_task_for_test\b/);
  assert.match(supportSource, /\npub\(super\) fn complete_recurring_parent_and_get_successor\b/);

  const testNames = ['batch.rs', 'create_update.rs', 'lifecycle_actions.rs', 'permanent_delete.rs']
    .flatMap((relativePath) =>
      [...read(relativePath).matchAll(/#\[test\]\s+fn\s+([a-zA-Z0-9_]+)/g)].map(
        ([, testName]) => testName,
      ),
    );
  assert.equal(new Set(testNames).size, testNames.length, 'split modules must not duplicate test functions');

  assert.match(
    read('lifecycle_actions.rs'),
    /\bfn\s+complete_task_rolls_back_when_reminder_relation_sync_enqueue_fails\b/,
  );
  assert.match(
    read('create_update.rs'),
    /\bfn\s+update_task_rolls_back_when_status_relation_sync_enqueue_fails\b/,
  );
  assert.match(
    read('batch.rs'),
    /\bfn\s+batch_reopen_tasks_rolls_back_when_successor_dependency_relation_sync_enqueue_fails\b/,
  );
  assert.match(
    read('permanent_delete.rs'),
    /\bfn\s+permanent_delete_task_emits_child_delete_envelopes_and_tombstones\b/,
  );
});
