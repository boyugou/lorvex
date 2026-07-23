import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

const facadePath = path.join(repoRoot, 'app/src-tauri/src/commands/tasks/reminders.rs');
const taskRemindersDir = path.join(repoRoot, 'app/src-tauri/src/commands/tasks/reminders');
const commandsRootPath = path.join(repoRoot, 'app/src-tauri/src/commands.rs');

function read(relativePath) {
  return fs.readFileSync(path.join(taskRemindersDir, relativePath), 'utf8');
}

test('Tauri task reminders stay split by responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  const commandsRootSource = fs.readFileSync(commandsRootPath, 'utf8');
  assert.ok(fs.existsSync(taskRemindersDir), 'commands/tasks/reminders/ should contain extracted modules');

  const moduleFiles = fs
    .readdirSync(taskRemindersDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, ['create.rs', 'delivery.rs', 'model.rs', 'read.rs', 'remove.rs', 'tests.rs']);

  for (const moduleName of ['create', 'delivery', 'model', 'read', 'remove']) {
    assert.match(
      facadeSource,
      rustModuleDeclarationPattern(moduleName),
      `task_reminders.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(facadeSource, /^#\[cfg\(test\)\]\nmod tests;$/m);
  assert.match(
    facadeSource,
    /pub use model::DueReminderEntry;/,
    'task_reminders.rs should re-export the public due-reminder type',
  );
  assert.match(
    facadeSource,
    /pub use read::\{\s*get_due_reminders,\s*get_task_reminders,\s*get_upcoming_reminders,?\s*\};/,
    'task_reminders.rs should re-export read IPC commands',
  );
  assert.match(
    facadeSource,
    /pub use create::add_task_reminder;/,
    'task_reminders.rs should re-export add_task_reminder',
  );
  assert.match(
    facadeSource,
    /pub\(crate\) use create::snooze_reminder_for_task_internal;/,
    'task_reminders.rs should preserve the native notification snooze helper export',
  );
  assert.match(
    facadeSource,
    /pub use remove::remove_task_reminder;/,
    'task_reminders.rs should re-export remove_task_reminder',
  );
  assert.match(
    facadeSource,
    /pub use delivery::mark_reminder_notified;/,
    'task_reminders.rs should re-export mark_reminder_notified',
  );
  assert.match(
    commandsRootSource,
    /pub\(crate\) use tasks::reminders::snooze_reminder_for_task_internal;/,
    'commands.rs should keep exposing the native snooze helper',
  );
  assert.doesNotMatch(
    commandsRootSource,
    /pub use tasks::reminders::\{[\s\S]*add_task_reminder[\s\S]*\};/,
    'commands.rs should not keep task reminder IPC re-exports for handler registration',
  );

  const facadeLineCount = facadeSource.trimEnd().split('\n').length;
  assert.ok(
    facadeLineCount <= 45,
    `task_reminders.rs should stay a small facade, got ${facadeLineCount} lines`,
  );
  assert.doesNotMatch(
    facadeSource,
    /\n#\[tauri::command\]|\n#\[test\]|\n(?:pub(?:\([^)]*\))?\s+)?fn\s+\w+|\n(?:pub(?:\([^)]*\))?\s+)?struct\s+\w+|\nimpl\s+/,
    'task_reminders.rs should not keep command implementations, helpers, types, or tests inline',
  );

  const modelSource = read('model.rs');
  assert.match(modelSource, /\npub struct DueReminderEntry\b/);
  assert.match(modelSource, /\npub\(super\) fn reminder_from_query_row\b/);
  assert.match(modelSource, /\npub\(super\) fn hydrate_due_reminder_entries\b/);
  assert.doesNotMatch(modelSource, /\n#\[tauri::command\]|\n#\[test\]/);

  const readSource = read('read.rs');
  assert.match(readSource, /\n#\[tauri::command\]\npub fn get_due_reminders\b/);
  assert.match(readSource, /\n#\[tauri::command\]\npub fn get_upcoming_reminders\b/);
  assert.match(readSource, /\n#\[tauri::command\]\npub fn get_task_reminders\b/);
  assert.match(readSource, /hydrate_due_reminder_entries/);
  assert.match(readSource, /get_reminders_for_task/);
  assert.doesNotMatch(readSource, /\n#\[test\]|\nfn add_task_reminder_with_conn\b|\nfn mark_reminder_notified_with_conn\b/);

  const createSource = read('create.rs');
  assert.match(createSource, /\n#\[tauri::command\]\npub fn add_task_reminder\b/);
  assert.match(createSource, /\npub\(crate\) fn snooze_reminder_for_task_internal\b/);
  assert.match(createSource, /\npub\(super\) fn add_task_reminder_with_conn\b/);
  assert.match(createSource, /\npub\(super\) fn add_task_reminder_in_transaction\b/);
  assert.match(createSource, /resolve_reminder_local_anchor/);
  assert.doesNotMatch(createSource, /\n#\[test\]|\nfn remove_task_reminder_with_conn\b|\nfn mark_reminder_notified_with_conn\b/);

  const removeSource = read('remove.rs');
  assert.match(removeSource, /\n#\[tauri::command\]\npub fn remove_task_reminder\b/);
  assert.match(removeSource, /\npub\(super\) fn remove_task_reminder_with_conn\b/);
  assert.match(removeSource, /load_task_reminder_pre_delete_snapshot/);
  assert.match(removeSource, /enqueue_task_reminder_delete/);
  assert.doesNotMatch(removeSource, /\n#\[test\]|\nfn add_task_reminder_with_conn\b|\nfn mark_reminder_notified_with_conn\b/);

  const deliverySource = read('delivery.rs');
  assert.match(deliverySource, /\n#\[tauri::command\]\npub fn mark_reminder_notified\b/);
  assert.match(deliverySource, /\npub\(crate\) fn mark_reminder_notified_with_conn\b/);
  assert.match(deliverySource, /task_reminder_delivery_state/);
  assert.doesNotMatch(deliverySource, /\n#\[test\]|\nfn add_task_reminder_with_conn\b|\nfn remove_task_reminder_with_conn\b/);

  const testsSource = read('tests.rs');
  const expectedTests = [
    'create_reminder_captures_original_local_time_and_tz',
    'create_reminder_leaves_anchor_null_when_no_timezone_preference',
    'create_reminder_ignores_cancelled_and_dismissed_history_for_cap',
    'add_task_reminder_inner_rejects_missing_task',
    'hydrate_due_reminder_entries_rejects_missing_task',
    'snooze_reminder_for_task_internal_creates_new_reminder_on_same_task',
    'snooze_reminder_for_task_internal_rejects_missing_task',
    'get_reminders_for_task_excludes_trashed_parent',
    'add_task_reminder_in_transaction_rolls_back_when_sync_enqueue_fails',
    'mark_reminder_notified_stamps_live_reminder',
    'mark_reminder_notified_skips_cancelled_reminder',
    'mark_reminder_notified_skips_archived_task_reminder',
    'mark_reminder_notified_unknown_id_is_idempotent_noop',
  ];
  const testNames = [...testsSource.matchAll(/\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
  assert.deepEqual(testNames.filter((name) => expectedTests.includes(name)).sort(), expectedTests.toSorted());
  assert.equal(new Set(testNames).size, testNames.length, 'task reminder test names should stay unique');
  assert.match(testsSource, /^use super::\*;/m);
});
