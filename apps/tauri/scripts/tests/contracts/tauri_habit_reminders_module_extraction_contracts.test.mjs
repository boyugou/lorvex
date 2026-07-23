import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

// Post-split: habit_reminders.rs/folder moved under commands/habits/reminders.
const facadePath = path.join(repoRoot, 'app/src-tauri/src/commands/habits/reminders.rs');
const habitRemindersDir = path.join(repoRoot, 'app/src-tauri/src/commands/habits/reminders');
const commandsRootPath = path.join(repoRoot, 'app/src-tauri/src/commands.rs');

function read(relativePath) {
  return fs.readFileSync(path.join(habitRemindersDir, relativePath), 'utf8');
}

test('Tauri habit reminders stay split by responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  const commandsRootSource = fs.readFileSync(commandsRootPath, 'utf8');
  assert.ok(fs.existsSync(habitRemindersDir), 'commands/habit_reminders/ should contain extracted modules');

  const moduleFiles = fs
    .readdirSync(habitRemindersDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, [
    'delivery.rs',
    'due.rs',
    'model.rs',
    'policy_commands.rs',
    'sync.rs',
    'tests.rs',
  ]);

  for (const moduleName of ['delivery', 'due', 'model', 'policy_commands', 'sync']) {
    assert.match(
      facadeSource,
      rustModuleDeclarationPattern(moduleName),
      `habit_reminders.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(facadeSource, /^#\[cfg\(test\)\]\nmod tests;$/m);
  assert.match(
    facadeSource,
    /pub use model::\{DueHabitReminder, HabitReminderPolicy\};/,
    'habit_reminders.rs should re-export public result types',
  );
  assert.match(
    facadeSource,
    /pub use policy_commands::\{\s*delete_habit_reminder_policy,\s*get_habit_reminder_policies,\s*upsert_habit_reminder_policy,\s*\};/,
    'habit_reminders.rs should re-export policy command IPC surface',
  );
  assert.match(
    facadeSource,
    /pub use due::get_due_habit_reminders;/,
    'habit_reminders.rs should re-export due reminder IPC surface',
  );
  assert.match(
    facadeSource,
    /pub use delivery::mark_habit_reminder_fired;/,
    'habit_reminders.rs should re-export delivery IPC surface',
  );
  assert.doesNotMatch(
    commandsRootSource,
    /pub use habits::reminders::\{\s*delete_habit_reminder_policy,\s*get_due_habit_reminders,\s*get_habit_reminder_policies,\s*mark_habit_reminder_fired,\s*upsert_habit_reminder_policy,\s*DueHabitReminder,\s*HabitReminderPolicy,\s*\};/,
    'commands.rs should not re-export habit reminder IPC for handler registration',
  );

  const facadeLineCount = facadeSource.trimEnd().split('\n').length;
  assert.ok(
    facadeLineCount <= 45,
    `habit_reminders.rs should stay a small facade, got ${facadeLineCount} lines`,
  );
  assert.doesNotMatch(
    facadeSource,
    /\n#\[tauri::command\]|\n#\[test\]|\nfn\s+\w+|\nstruct\s+\w+|\nimpl\s+/,
    'habit_reminders.rs should not keep command implementations, helpers, types, or tests inline',
  );

  const modelSource = read('model.rs');
  assert.match(modelSource, /\npub struct HabitReminderPolicy\b/);
  assert.match(modelSource, /\npub struct DueHabitReminder\b/);
  assert.match(modelSource, /\npub\(super\) struct HabitReminderCandidate\b/);
  assert.match(modelSource, /\npub\(super\) fn policy_from_row\b/);
  assert.doesNotMatch(modelSource, /\n#\[tauri::command\]|\n#\[test\]/);

  const syncSource = read('sync.rs');
  for (const name of [
    'enqueue_habit_reminder_policy_upsert',
    'enqueue_habit_reminder_policy_delete',
    'load_habit_reminder_policy_pre_delete_snapshot',
  ]) {
    assert.match(syncSource, new RegExp(`\\npub\\(super\\) fn ${name}\\b`), `sync.rs should own ${name}`);
  }
  assert.match(syncSource, /ENTITY_HABIT_REMINDER_POLICY/);
  assert.doesNotMatch(syncSource, /\n#\[tauri::command\]|\n#\[test\]/);

  const policySource = read('policy_commands.rs');
  assert.match(policySource, /\n#\[tauri::command\]\npub fn get_habit_reminder_policies\b/);
  assert.match(policySource, /\n#\[tauri::command\]\npub fn upsert_habit_reminder_policy\b/);
  assert.match(policySource, /\n#\[tauri::command\]\npub fn delete_habit_reminder_policy\b/);
  assert.match(policySource, /\npub\(super\) fn upsert_habit_reminder_policy_with_conn\b/);
  assert.match(policySource, /\nfn delete_habit_reminder_policy_with_conn\b/);
  assert.doesNotMatch(policySource, /\nfn get_due_habit_reminders_with_conn_at\b|\nfn mark_habit_reminder_fired_with_conn\b|\n#\[test\]/);

  const dueSource = read('due.rs');
  assert.match(dueSource, /\n#\[tauri::command\]\npub fn get_due_habit_reminders\b/);
  for (const name of [
    'reminder_was_sent_on_local_day',
    'get_due_habit_reminders_with_conn_at',
    'habit_reminder_is_due',
    'current_habit_period_progress',
    'due_habit_reminder_clock_at',
  ]) {
    assert.match(dueSource, new RegExp(`\\npub\\(super\\) fn ${name}\\b|\\nfn ${name}\\b`), `due.rs should own ${name}`);
  }
  assert.doesNotMatch(dueSource, /\nfn mark_habit_reminder_fired_with_conn\b|\n#\[test\]/);

  const deliverySource = read('delivery.rs');
  assert.match(deliverySource, /\n#\[tauri::command\]\npub fn mark_habit_reminder_fired\b/);
  assert.match(deliverySource, /\npub\(super\) fn mark_habit_reminder_fired_with_conn\b/);
  assert.doesNotMatch(deliverySource, /\nfn get_due_habit_reminders_with_conn_at\b|\n#\[test\]/);

  const testsSource = read('tests.rs');
  const expectedTests = [
    'upsert_habit_reminder_policy_with_conn_rejects_missing_habit',
    'upsert_habit_reminder_policy_with_conn_surfaces_habit_lookup_failures',
    'upsert_habit_reminder_policy_with_conn_updates_version_for_existing_policy',
    'due_habit_reminder_clock_at_uses_timezone_calendar_day',
    'due_habit_reminder_clock_at_rejects_invalid_timezone_name',
    'get_due_habit_reminders_with_conn_at_skips_policies_already_reminded_today',
    'reminder_was_sent_on_local_day_propagates_db_errors',
    'get_due_habit_reminders_with_conn_at_respects_weekly_schedule_days',
    'get_due_habit_reminders_with_conn_at_suppresses_slots_after_target_count_is_met',
    'mark_habit_reminder_fired_with_conn_updates_local_delivery_state',
    'upsert_habit_reminder_policy_with_conn_allows_multiple_slots_per_habit',
    'upsert_habit_reminder_policy_with_conn_rejects_duplicate_slot_times_for_same_habit',
    'upsert_habit_reminder_policy_with_conn_rejects_updates_that_collide_with_existing_slot',
  ];
  const testNames = [...testsSource.matchAll(/\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
  assert.deepEqual(testNames.filter((name) => expectedTests.includes(name)).sort(), expectedTests.toSorted());
  assert.equal(new Set(testNames).size, testNames.length, 'habit reminder test names should stay unique');
  assert.match(testsSource, /^use super::\*;/m);
});
