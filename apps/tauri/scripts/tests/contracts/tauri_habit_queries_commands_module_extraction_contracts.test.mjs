import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

const facadePath = path.join(repoRoot, 'app/src-tauri/src/commands/habits/queries/commands.rs');
const moduleRootPath = path.join(repoRoot, 'app/src-tauri/src/commands/habits/queries/mod.rs');
const writesPath = path.join(repoRoot, 'app/src-tauri/src/commands/habits/queries/writes.rs');
const commandsDir = path.join(repoRoot, 'app/src-tauri/src/commands/habits/queries/commands');

function read(relativePath) {
  return fs.readFileSync(path.join(commandsDir, relativePath), 'utf8');
}

test('Tauri habit query commands stay split by responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  const moduleRootSource = fs.readFileSync(moduleRootPath, 'utf8');
  const writesSource = fs.readFileSync(writesPath, 'utf8');
  assert.ok(fs.existsSync(commandsDir), 'habit_queries/commands/ should contain extracted modules');

  const moduleFiles = fs
    .readdirSync(commandsDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, [
    'cache.rs',
    'completion_adjust.rs',
    'helpers.rs',
    'stats.rs',
    'streak_queries.rs',
    'tests.rs',
    'today.rs',
  ]);

  for (const moduleName of [
    'cache',
    'completion_adjust',
    'helpers',
    'stats',
    'streak_queries',
    'today',
  ]) {
    assert.match(
      facadeSource,
      rustModuleDeclarationPattern(moduleName),
      `commands.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(facadeSource, /^#\[cfg\(test\)\]\nmod tests;$/m);
  assert.match(
    facadeSource,
    /pub\(crate\) use cache::clear_best_streak_cache;/,
    'commands.rs should re-export the bulk cache invalidation hook used outside this module',
  );
  assert.match(
    facadeSource,
    /pub\(crate\) use cache::invalidate_best_streak_cache;/,
    'commands.rs should re-export the single-habit cache invalidation hook used by writes.rs',
  );
  assert.match(
    facadeSource,
    /pub use completion_adjust::adjust_habit_completion;/,
    'commands.rs should re-export the completion mutation command',
  );
  assert.match(
    facadeSource,
    /pub use stats::get_habits_with_stats;/,
    'commands.rs should re-export the Habits view stats command',
  );
  assert.match(
    facadeSource,
    /pub use today::get_todays_habits;/,
    'commands.rs should re-export the Today view habit command',
  );

  const facadeLineCount = facadeSource.trimEnd().split('\n').length;
  assert.ok(
    facadeLineCount <= 45,
    `habit query commands facade should stay small, got ${facadeLineCount} lines`,
  );
  assert.doesNotMatch(
    facadeSource,
    /\n#\[tauri::command\]|\n#\[test\]|\nfn\s+\w+|\ntype\s+\w+|\nstruct\s+\w+|\nimpl\s+/,
    'commands.rs should not keep command implementations, helper types, or tests inline',
  );

  assert.match(
    moduleRootSource,
    /pub\(crate\) use commands::clear_best_streak_cache;/,
    'habit_queries/mod.rs should keep exposing bulk cache invalidation to parent modules',
  );
  assert.match(
    moduleRootSource,
    /pub use commands::\{adjust_habit_completion, get_habits_with_stats, get_todays_habits\};/,
    'habit_queries/mod.rs should keep exposing the public Tauri habit query command surface',
  );
  assert.match(
    writesSource,
    /super::commands::invalidate_best_streak_cache\(habit_id\);/,
    'writes.rs should keep invalidating the best-streak cache through the commands facade',
  );

  const cacheSource = read('cache.rs');
  for (const name of [
    'best_streak_cache',
    'clear_best_streak_cache_for_test',
    'reset_best_streak_full_history_scan_count_for_test',
    'best_streak_full_history_scan_count_for_test',
    'record_best_streak_full_history_scan_for_test',
    'invalidate_best_streak_cache',
    'clear_best_streak_cache',
  ]) {
    assert.match(cacheSource, new RegExp(`\\bfn\\s+${name}\\b`), `cache.rs should own ${name}`);
  }

  const helpersSource = read('helpers.rs');
  for (const name of [
    'progress_kind_for',
    'frequency_type_from_row',
    'parse_habit_completion_date',
    'load_existing_completion_value',
  ]) {
    assert.match(helpersSource, new RegExp(`\\bfn\\s+${name}\\b`), `helpers.rs should own ${name}`);
  }
  assert.match(helpersSource, /\n(?:pub\(super\)\s+)?type HabitRow\b/);

  const statsSource = read('stats.rs');
  assert.match(statsSource, /\n#\[tauri::command\]\npub fn get_habits_with_stats\b/);
  assert.match(statsSource, /\npub\(crate\) fn gather_habits_with_stats\b/);
  assert.match(statsSource, /\ntype HabitStats\b/);
  assert.doesNotMatch(statsSource, /\n#\[test\]/);

  const todaySource = read('today.rs');
  assert.match(todaySource, /\n#\[tauri::command\]\npub fn get_todays_habits\b/);
  assert.doesNotMatch(todaySource, /\nfn compute_all_streaks\b|\n#\[test\]/);

  const completionSource = read('completion_adjust.rs');
  assert.match(completionSource, /\n#\[tauri::command\]\npub fn adjust_habit_completion\b/);
  assert.doesNotMatch(completionSource, /\nfn compute_current_streak\b|\n#\[test\]/);

  const streakSource = read('streak_queries.rs');
  assert.match(streakSource, /\npub\(super\) fn compute_all_streaks\b/);
  assert.match(streakSource, /\npub\(super\) fn compute_current_streak\b/);
  assert.doesNotMatch(streakSource, /\n#\[tauri::command\]|\n#\[test\]/);

  const testsSource = read('tests.rs');
  const expectedTests = [
    'compute_all_streaks_rejects_invalid_completed_date',
    'compute_current_streak_rejects_invalid_completed_date',
    'current_streaks_ignore_future_completion_dates',
    'load_existing_completion_value_surfaces_lookup_failures',
    'get_habits_with_stats_bounded_scan_scales_to_large_history',
    'best_streak_cache_hit_short_circuits_full_history_scan',
  ];
  const testNames = [...testsSource.matchAll(/\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
  assert.deepEqual(testNames.filter((name) => expectedTests.includes(name)).sort(), expectedTests.toSorted());
  assert.equal(new Set(testNames).size, testNames.length, 'habit query command test names should stay unique');
  assert.match(testsSource, /^use super::\*;/m);
});
