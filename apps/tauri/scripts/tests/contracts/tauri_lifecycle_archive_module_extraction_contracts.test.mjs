import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

const facadePath = path.join(repoRoot, 'app/src-tauri/src/commands/tasks/lifecycle/archive.rs');
const archiveDir = path.join(repoRoot, 'app/src-tauri/src/commands/tasks/lifecycle/archive');
const lifecycleRootPath = path.join(repoRoot, 'app/src-tauri/src/commands/tasks/lifecycle/mod.rs');

function read(relativePath) {
  return fs.readFileSync(path.join(archiveDir, relativePath), 'utf8');
}

test('Tauri task lifecycle archive stays split by responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  const lifecycleRootSource = fs.readFileSync(lifecycleRootPath, 'utf8');
  assert.ok(fs.existsSync(archiveDir), 'lifecycle/archive/ should contain extracted modules');

  const moduleFiles = fs
    .readdirSync(archiveDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, [
    'archive_commands.rs',
    'empty_trash.rs',
    'query.rs',
    'startup_purge.rs',
    'tests.rs',
  ]);

  for (const moduleName of ['archive_commands', 'empty_trash', 'query', 'startup_purge']) {
    assert.match(
      facadeSource,
      rustModuleDeclarationPattern(moduleName),
      `archive.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(facadeSource, /^#\[cfg\(test\)\]\nmod tests;$/m);
  assert.match(
    facadeSource,
    /pub const TRASH_RETENTION_DAYS: i64 = lorvex_sync::startup_trash_purge::TRASH_RETENTION_DAYS;/,
    'archive.rs should keep the public Trash retention constant',
  );
  assert.match(
    facadeSource,
    /pub use archive_commands::\{archive_task, restore_task_from_trash\};/,
    'archive.rs should re-export archive and restore IPC commands',
  );
  assert.match(
    facadeSource,
    /pub use empty_trash::\{empty_trash, EmptyTrashResult\};/,
    'archive.rs should re-export empty_trash IPC command and result type',
  );
  assert.match(
    facadeSource,
    /pub use query::\{get_archived_tasks, ArchivedTasksResult\};/,
    'archive.rs should re-export archived task query IPC command and result type',
  );
  assert.match(
    facadeSource,
    /pub use startup_purge::run_startup_trash_purge;/,
    'archive.rs should re-export startup purge hook',
  );
  assert.match(
    lifecycleRootSource,
    /pub\(crate\) use archive::run_startup_trash_purge;/,
    'lifecycle/mod.rs should keep exposing startup purge to the db connection startup path',
  );
  assert.match(
    lifecycleRootSource,
    /pub use archive::\{\s*archive_task,\s*empty_trash,\s*get_archived_tasks,\s*restore_task_from_trash,\s*ArchivedTasksResult,\s*EmptyTrashResult,\s*\};/,
    'lifecycle/mod.rs should keep exposing the public Trash command surface',
  );

  const facadeLineCount = facadeSource.trimEnd().split('\n').length;
  assert.ok(facadeLineCount <= 75, `archive.rs should stay a small facade, got ${facadeLineCount} lines`);
  assert.doesNotMatch(
    facadeSource,
    /\n#\[tauri::command\]|\n#\[test\]|\n(?:pub(?:\([^)]*\))?\s+)?fn\s+\w+|\n(?:pub(?:\([^)]*\))?\s+)?struct\s+\w+|\nimpl\s+/,
    'archive.rs should not keep command implementations, helper types, or tests inline',
  );

  const archiveCommandsSource = read('archive_commands.rs');
  assert.match(archiveCommandsSource, /\n#\[tauri::command\]\npub fn archive_task\b/);
  assert.match(archiveCommandsSource, /\n#\[tauri::command\]\npub fn restore_task_from_trash\b/);
  assert.match(archiveCommandsSource, /\npub\(crate\) fn archive_task_with_conn\b/);
  assert.match(archiveCommandsSource, /\npub\(crate\) fn restore_task_from_trash_with_conn\b/);
  assert.doesNotMatch(archiveCommandsSource, /\n#\[test\]|\npub fn empty_trash\b|\npub fn get_archived_tasks\b/);

  const querySource = read('query.rs');
  assert.match(querySource, /\nconst GET_ARCHIVED_TASKS_LIMIT: u32 = 1_000;/);
  assert.match(querySource, /\npub struct ArchivedTasksResult\b/);
  assert.match(querySource, /\n#\[tauri::command\]\npub fn get_archived_tasks\b/);
  assert.match(querySource, /\nfn get_archived_tasks_inner\b/);
  assert.doesNotMatch(querySource, /\n#\[test\]|\npub fn empty_trash\b|\npub fn archive_task\b/);

  const emptyTrashSource = read('empty_trash.rs');
  assert.match(emptyTrashSource, /\npub struct EmptyTrashResult\b/);
  assert.match(emptyTrashSource, /\n#\[tauri::command\]\npub fn empty_trash\b/);
  assert.match(emptyTrashSource, /\npub\(crate\) fn empty_trash_with_conn\b/);
  assert.match(emptyTrashSource, /startup_trash_purge::purge_expired_archived_tasks/);
  assert.doesNotMatch(emptyTrashSource, /\n#\[test\]|\npub fn run_startup_trash_purge\b|\npub fn get_archived_tasks\b/);

  const startupSource = read('startup_purge.rs');
  assert.match(startupSource, /\npub fn run_startup_trash_purge\b/);
  assert.match(startupSource, /\n(?:pub\(super\) )?fn log_startup_trash_purge_report\b/);
  assert.match(startupSource, /\n(?:pub\(super\) )?fn log_startup_trash_purge_failure\b/);
  assert.match(startupSource, /maintenance\.startup_trash_purge\.purged/);
  assert.match(startupSource, /maintenance\.startup_trash_purge\.failed/);
  assert.doesNotMatch(startupSource, /\neprintln!\s*\(|\n#\[test\]/);

  const testsSource = read('tests.rs');
  const expectedTests = [
    'empty_trash_task_tag_delete_envelope_carries_version_and_created_at',
    'empty_trash_task_calendar_event_link_delete_envelope_carries_version_and_created_at',
    'archive_task_sets_archived_at_and_enqueues_upsert',
    'archive_task_rejects_already_archived',
    'restore_task_clears_archived_at',
    'restore_task_rejects_non_archived',
    'empty_trash_purges_only_rows_older_than_retention',
    'empty_trash_with_empty_window_is_noop',
    'startup_trash_purge_writes_diagnostic_not_ai_changelog',
    'startup_trash_purge_success_persists_structured_diagnostic',
    'startup_trash_purge_failure_persists_structured_diagnostic',
    'empty_trash_emits_child_delete_envelopes_and_tombstones',
    'archive_removes_task_from_current_focus_items',
    'empty_trash_reenqueues_parent_aggregate_upserts_for_focus_and_schedule_days',
  ];
  const testNames = [...testsSource.matchAll(/\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
  assert.deepEqual(testNames.filter((name) => expectedTests.includes(name)).sort(), expectedTests.toSorted());
  assert.equal(new Set(testNames).size, testNames.length, 'archive lifecycle test names should stay unique');
  assert.match(testsSource, /^use super::\*;/m);
});
