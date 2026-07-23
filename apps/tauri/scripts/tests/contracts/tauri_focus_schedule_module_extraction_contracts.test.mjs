import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

const facadePath = path.join(
  repoRoot,
  'app/src-tauri/src/commands/planning/focus_schedule.rs',
);
const focusScheduleDir = path.join(
  repoRoot,
  'app/src-tauri/src/commands/planning/focus_schedule',
);
const planningModPath = path.join(repoRoot, 'app/src-tauri/src/commands/planning/mod.rs');

function read(relativePath) {
  return fs.readFileSync(path.join(focusScheduleDir, relativePath), 'utf8');
}

test('Tauri focus schedule planning command stays split by responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  const planningModSource = fs.readFileSync(planningModPath, 'utf8');
  assert.ok(
    fs.existsSync(focusScheduleDir),
    'commands/planning/focus_schedule/ should contain extracted modules',
  );

  const moduleFiles = fs
    .readdirSync(focusScheduleDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, [
    'blocks.rs',
    'dismiss.rs',
    'read.rs',
    'sync.rs',
    'tests.rs',
    'write.rs',
  ]);

  for (const moduleName of ['blocks', 'dismiss', 'read', 'sync', 'write']) {
    assert.match(
      facadeSource,
      rustModuleDeclarationPattern(moduleName),
      `focus_schedule.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(facadeSource, /^#\[cfg\(test\)\]\nmod tests;$/m);
  assert.match(
    facadeSource,
    /pub use dismiss::dismiss_focus_schedule;/,
    'focus_schedule.rs should re-export dismiss_focus_schedule',
  );
  assert.match(
    facadeSource,
    /pub use read::get_focus_schedule;/,
    'focus_schedule.rs should re-export get_focus_schedule',
  );
  assert.match(
    facadeSource,
    /pub use write::update_focus_schedule_blocks;/,
    'focus_schedule.rs should re-export update_focus_schedule_blocks',
  );
  assert.match(
    planningModSource,
    /pub use focus_schedule::\{[\s\S]*dismiss_focus_schedule[\s\S]*get_focus_schedule[\s\S]*update_focus_schedule_blocks[\s\S]*\};/,
    'planning/mod.rs should keep exposing the existing focus schedule IPC surface',
  );
  assert.ok(
    facadeSource.trimEnd().split('\n').length <= 35,
    'focus_schedule.rs should stay a small facade after extraction',
  );
  assert.doesNotMatch(
    facadeSource,
    /\n#\[tauri::command\]|\n#\[test\]|\n(?:pub(?:\([^)]*\))?\s+)?fn\s+\w+|\n(?:pub(?:\([^)]*\))?\s+)?struct\s+\w+|\nimpl\s+/,
    'focus_schedule.rs should not keep command implementations, helpers, types, or tests inline',
  );

  const blocksSource = read('blocks.rs');
  assert.match(blocksSource, /\npub\(super\) fn query_schedule_blocks\b/);
  assert.match(blocksSource, /\npub\(super\) fn normalize_schedule_block_entries\b/);
  assert.match(blocksSource, /\npub\(crate\) fn validate_schedule_block_ids\b/);
  assert.match(blocksSource, /parse_hhmm_to_minutes/);
  assert.doesNotMatch(
    blocksSource,
    /\npub\(super\) fn materialize_schedule_blocks\b/,
    'blocks.rs should normalize IPC blocks only; storage materialization is owned by lorvex-store',
  );
  assert.doesNotMatch(blocksSource, /\n#\[tauri::command\]|\n#\[test\]|\nfn update_focus_schedule_blocks_with_conn\b/);

  const readSource = read('read.rs');
  assert.match(readSource, /\n#\[tauri::command\]\npub fn get_focus_schedule\b/);
  assert.match(readSource, /\npub\(super\) fn get_focus_schedule_with_conn\b/);
  assert.match(readSource, /query_schedule_blocks/);
  assert.match(readSource, /fetch_ordered_tasks_by_ids/);
  assert.doesNotMatch(readSource, /\n#\[test\]|\nfn update_focus_schedule_blocks_with_conn\b|\nfn dismiss_focus_schedule_with_conn\b/);

  const syncSource = read('sync.rs');
  assert.match(syncSource, /\npub\(super\) fn enqueue_focus_schedule_sync\b/);
  assert.match(syncSource, /build_aggregate_payload/);
  assert.match(syncSource, /enqueue_to_outbox_typed/);
  assert.doesNotMatch(syncSource, /\n#\[tauri::command\]|\n#\[test\]/);

  const writeSource = read('write.rs');
  assert.match(writeSource, /\n#\[tauri::command\]\npub fn update_focus_schedule_blocks\b/);
  assert.match(writeSource, /\npub\(super\) fn update_focus_schedule_blocks_with_conn\b/);
  assert.match(writeSource, /validate_schedule_block_ids/);
  assert.match(
    writeSource,
    /lorvex_store::focus_schedule_blocks::materialize_schedule_blocks/,
    'write.rs should call the shared store focus-schedule block materializer',
  );
  assert.match(writeSource, /enqueue_focus_schedule_sync/);
  assert.match(writeSource, /enqueue_current_focus_upsert_for_date/);
  assert.doesNotMatch(writeSource, /\n#\[test\]|\nfn query_schedule_blocks\b|\nfn dismiss_focus_schedule_with_conn\b/);

  const dismissSource = read('dismiss.rs');
  assert.match(dismissSource, /\n#\[tauri::command\]\npub fn dismiss_focus_schedule\b/);
  assert.match(dismissSource, /\npub\(super\) fn dismiss_focus_schedule_with_conn\b/);
  assert.match(dismissSource, /build_aggregate_payload/);
  assert.match(dismissSource, /get_focus_schedule_with_conn/);
  assert.doesNotMatch(dismissSource, /\n#\[test\]|\nfn update_focus_schedule_blocks_with_conn\b/);

  const testsSource = read('tests.rs');
  // Behaviour-contract — each domain area inside the focus_schedule
  // module must keep at least one regression test in tests.rs. The
  // earlier shape pinned an exact test-name list, which forced any
  // refactor that consolidated two redundant cases (e.g. merging
  // `query_schedule_blocks_clears_non_task_task_ids` into
  // `normalize_schedule_block_entries_clears_non_task_task_ids`) to
  // also touch this contract test, even though the surface coverage
  // didn't regress. The relaxed shape requires at least one test per
  // domain area, so a future contributor cannot delete the last test
  // for a slice silently.
  const requiredTestPrefixes = [
    'normalize_schedule_block_entries',
    'materialize_schedule_blocks',
    'update_focus_schedule_blocks_with_conn',
    'get_focus_schedule_with_conn',
    'validate_schedule_block_ids',
    'dismiss_focus_schedule_with_conn',
  ];
  const testNames = [...testsSource.matchAll(/\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
  for (const prefix of requiredTestPrefixes) {
    assert.ok(
      testNames.some((name) => name.startsWith(prefix)),
      `focus_schedule/tests.rs should keep at least one regression test starting with "${prefix}"`,
    );
  }
  assert.equal(new Set(testNames).size, testNames.length, 'focus schedule test names should stay unique');
  assert.match(testsSource, /^use super::\*;/m);
});
