import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

const facadePath = path.join(
  repoRoot,
  'app/src-tauri/src/commands/tasks/updates.rs',
);
const updatesDir = path.join(
  repoRoot,
  'app/src-tauri/src/commands/tasks/updates',
);
const capturePath = path.join(
  repoRoot,
  'app/src-tauri/src/commands/tasks/capture/mod.rs',
);

function read(relativePath) {
  return fs.readFileSync(path.join(updatesDir, relativePath), 'utf8');
}

test('Tauri task update commands stay split by update responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  const captureSource = fs.readFileSync(capturePath, 'utf8');
  assert.ok(
    fs.existsSync(updatesDir),
    'task_commands/updates/ should contain extracted modules',
  );

  const moduleFiles = fs
    .readdirSync(updatesDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, [
    'body.rs',
    'command.rs',
    'flush.rs',
    'tests.rs',
  ]);

  for (const moduleName of [
    'body',
    'command',
    'flush',
  ]) {
    assert.match(
      facadeSource,
      rustModuleDeclarationPattern(moduleName),
      `updates.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(facadeSource, /^#\[cfg\(test\)\]\nmod tests;$/m);
  assert.doesNotMatch(
    facadeSource,
    /pub use body::append_to_task_body;/,
    'updates.rs should not re-export the retired append_to_task_body IPC command',
  );
  assert.match(
    facadeSource,
    /pub use command::update_task;/,
    'updates.rs should re-export update_task',
  );
  assert.match(
    facadeSource,
    /pub\(crate\) use command::\{[^}]*update_task_inner_with_conn[^}]*\};/,
    'updates.rs should preserve the test undo replay helper export',
  );
  assert.match(
    facadeSource,
    /pub\(crate\) use command::\{[^}]*update_task_internal[^}]*\};/,
    'updates.rs should preserve the undo sibling update replay export',
  );

  const facadeLineCount = facadeSource.trimEnd().split('\n').length;
  assert.ok(
    facadeLineCount <= 55,
    `updates.rs should stay a small facade, got ${facadeLineCount} lines`,
  );
  assert.doesNotMatch(
    facadeSource,
    /\n#\[tauri::command\]|\n#\[test\]|\n(?:pub(?:\([^)]*\))?\s+)?fn\s+\w+|\n(?:pub(?:\([^)]*\))?\s+)?const\s+\w+|\nimpl\s+/,
    'updates.rs should not keep command implementations, helpers, constants, or tests inline',
  );

  const commandSource = read('command.rs');
  assert.match(commandSource, /\n#\[tauri::command\]\npub fn update_task\b/);
  assert.match(commandSource, /\npub\(crate\) fn update_task_inner\b/);
  assert.match(commandSource, /\npub\(crate\) fn update_task_inner_with_conn\b/);
  assert.match(commandSource, /build_update_undo_token/);
  assert.match(commandSource, /update_task_internal/);
  assert.doesNotMatch(
    commandSource,
    /\n#\[test\]|\nfn append_to_task_body\b|\nfn parse_tag_value_from_update\b/,
  );

  const bodySource = read('body.rs');
  assert.doesNotMatch(bodySource, /\n#\[tauri::command\]\npub fn append_to_task_body\b/);
  assert.match(bodySource, /\npub\(crate\) fn append_to_task_body_with_conn\b/);
  assert.match(bodySource, /append_to_task_body\(/);
  assert.match(bodySource, /finalize_task_mutation/);
  assert.doesNotMatch(
    bodySource,
    /\n#\[test\]|\nfn update_task_internal\b/,
  );

  assert.match(commandSource, /\npub\(crate\) fn update_task_internal\b/);

  const flushSource = read('flush.rs');
  assert.doesNotMatch(flushSource, /\n#\[tauri::command\]|\n#\[test\]/);

  const testsSource = read('tests.rs');
  const expectedTests = [
    'append_to_task_body_with_conn_rejects_whitespace_only_text',
    'append_to_task_body_with_conn_appends_text_and_enqueues_outbox',
    'append_to_task_body_with_conn_rejects_missing_task',
    'update_task_undo_roundtrip_restores_title_priority_due_date',
    'update_task_public_undo_succeeds_without_redo_token',
    'consecutive_updates_coalesce_and_latest_undo_restores_prior_edit',
    'update_task_undo_after_forward_rows_synced_emits_compensating_upsert',
    'update_task_undo_roundtrip_restores_rename',
    'update_task_undo_roundtrip_restores_priority_change',
    'update_task_undo_roundtrip_restores_recurrence_rule',
  ];
  const testNames = [...testsSource.matchAll(/\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map(
    (match) => match[1],
  );
  assert.deepEqual(testNames.filter((name) => expectedTests.includes(name)).sort(), expectedTests.toSorted());
  assert.equal(new Set(testNames).size, testNames.length, 'task update test names should stay unique');
  assert.match(testsSource, /^use super::\*;/m);

  assert.doesNotMatch(
    captureSource,
    /updates\.rs:\d+/,
    'capture.rs comments should not point at stale line numbers in the pre-split hotspot',
  );
});
