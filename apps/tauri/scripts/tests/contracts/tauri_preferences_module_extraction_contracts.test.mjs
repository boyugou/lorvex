import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

const facadePath = path.join(repoRoot, 'app/src-tauri/src/commands/settings/preferences.rs');
const preferencesDir = path.join(repoRoot, 'app/src-tauri/src/commands/settings/preferences');
const commandsRootPath = path.join(repoRoot, 'app/src-tauri/src/commands.rs');

function read(relativePath) {
  return fs.readFileSync(path.join(preferencesDir, relativePath), 'utf8');
}

test('Tauri preferences stay split by responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  const commandsRootSource = fs.readFileSync(commandsRootPath, 'utf8');
  assert.ok(fs.existsSync(preferencesDir), 'commands/preferences/ should contain extracted modules');

  const moduleFiles = fs
    .readdirSync(preferencesDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, ['reads.rs', 'tests.rs', 'timezone_reanchor.rs', 'write.rs']);

  for (const moduleName of ['reads', 'timezone_reanchor', 'write']) {
    assert.match(
      facadeSource,
      rustModuleDeclarationPattern(moduleName),
      `preferences.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(facadeSource, /^#\[cfg\(test\)\]\nmod tests;$/m);
  assert.match(
    facadeSource,
    /pub use reads::\{get_default_filesystem_bridge_root_path, get_preference, get_preferences\};/,
    'preferences.rs should re-export preference read commands',
  );
  assert.match(
    facadeSource,
    /pub use write::set_preference;/,
    'preferences.rs should re-export the preference write command',
  );
  assert.match(
    facadeSource,
    /^#\[cfg\(test\)\]\npub\(crate\) use reads::default_sync_backend_kind;$/m,
    'preferences.rs should keep exposing default backend fallback helper for status tests',
  );
  assert.doesNotMatch(
    commandsRootSource,
    /pub use settings::preferences::\{\s*get_default_filesystem_bridge_root_path,\s*get_preference,\s*get_preferences,\s*set_preference,\s*\};/,
    'commands.rs should not re-export preferences IPC for handler registration',
  );
  assert.match(
    commandsRootSource,
    /pub\(crate\) use settings::preferences::default_sync_backend_kind;/,
    'commands.rs should keep exposing default_sync_backend_kind to sync status tests',
  );

  const facadeLineCount = facadeSource.trimEnd().split('\n').length;
  assert.ok(facadeLineCount <= 25, `preferences.rs should stay a small facade, got ${facadeLineCount} lines`);
  assert.doesNotMatch(
    facadeSource,
    /\n#\[tauri::command\]|\n#\[test\]|\n(?:pub(?:\([^)]*\))?\s+)?fn\s+\w+|\n(?:pub(?:\([^)]*\))?\s+)?const\s+\w+|\n(?:pub(?:\([^)]*\))?\s+)?struct\s+\w+|\nimpl\s+/,
    'preferences.rs should not keep command implementations, helpers, constants, types, or tests inline',
  );

  const readsSource = read('reads.rs');
  assert.match(readsSource, /\n#\[tauri::command\]\npub fn get_preference\b/);
  assert.match(readsSource, /\n#\[tauri::command\]\npub fn get_preferences\b/);
  assert.match(readsSource, /\n#\[tauri::command\]\npub fn get_default_filesystem_bridge_root_path\b/);
  assert.match(readsSource, /\npub\(crate\) fn default_sync_backend_kind\b/);
  assert.match(readsSource, /preferences\.corrupt_row/);
  assert.doesNotMatch(readsSource, /\n#\[test\]|\nfn set_preference_with_conn\b|\nfn reanchor_task_reminders_on_timezone_change\b/);

  const timezoneSource = read('timezone_reanchor.rs');
  assert.match(timezoneSource, /\npub\(super\) fn reanchor_task_reminders_on_timezone_change\b/);
  assert.match(timezoneSource, /\nfn parse_hhmm\b/);
  assert.match(timezoneSource, /enqueue_task_reminder_upsert/);
  assert.doesNotMatch(timezoneSource, /\n#\[tauri::command\]|\n#\[test\]|\nfn set_preference_with_conn\b/);

  const writeSource = read('write.rs');
  assert.match(writeSource, /\n#\[tauri::command\]\npub fn set_preference\b/);
  assert.match(writeSource, /\npub\(super\) fn set_preference_with_conn\b/);
  assert.match(writeSource, /use lorvex_domain::validation::\{[\s\S]*KV_KEY_MAX_CHARS,\s*KV_VALUE_MAX_BYTES[\s\S]*\};/);
  assert.doesNotMatch(writeSource, /\n(?:pub\(super\) )?const MAX_PREFERENCE_KEY_LEN\b/);
  assert.doesNotMatch(writeSource, /\n(?:pub\(super\) )?const MAX_PREFERENCE_VALUE_LEN\b/);
  assert.doesNotMatch(writeSource, /validate_path_shaped_preference_value/);
  assert.match(writeSource, /PREF_LANGUAGE/);
  assert.match(writeSource, /reanchor_task_reminders_on_timezone_change/);
  assert.doesNotMatch(writeSource, /\n#\[test\]|\nfn get_preference_inner\b/);

  const testsSource = read('tests.rs');
  const expectedTests = [
    'pref_timezone_change_reanchors_pending_reminders',
    'pref_timezone_change_skips_legacy_reminders_without_original_tz',
    'pref_timezone_change_skips_notified_reminders',
    'pref_timezone_change_leaves_past_reminders_alone',
    'set_preference_with_conn_rejects_oversized_key_and_value',
    'set_preference_with_conn_clearing_existing_value_enqueues_delete',
    'set_preference_with_conn_clearing_existing_value_surfaces_lookup_failures',
    'set_preference_with_conn_rejects_malformed_json_value',
    'set_preference_with_conn_rejects_unknown_keys',
    'set_preference_with_conn_rejects_memory_lock_enabled_on_platforms_without_biometrics',
    'set_preference_with_conn_accepts_memory_lock_enabled_on_biometric_platforms',
  ];
  const testNames = [...testsSource.matchAll(/\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
  assert.deepEqual(testNames.filter((name) => expectedTests.includes(name)).sort(), expectedTests.toSorted());
  assert.equal(new Set(testNames).size, testNames.length, 'preference test names should stay unique');
  assert.match(testsSource, /^use super::\*;/m);
});
