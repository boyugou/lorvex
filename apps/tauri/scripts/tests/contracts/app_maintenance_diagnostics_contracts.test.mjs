import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('startup trash purge diagnostics persist instead of writing stderr', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/lifecycle/archive/startup_purge.rs'),
    'utf8',
  );
  const functionBody = source.match(
    /pub fn run_startup_trash_purge\([\s\S]*?^(?:pub\(super\) )?fn log_startup_trash_purge_failure[\s\S]*?\n\}/m,
  );

  assert.ok(functionBody, 'run_startup_trash_purge function must remain explicit');
  assert.doesNotMatch(
    functionBody[0],
    /eprintln!\s*\(/,
    'startup trash purge and its diagnostic helpers must not write stderr directly in packaged app builds',
  );
  assert.match(source, /maintenance\.startup_trash_purge\.purged/);
  assert.match(source, /maintenance\.startup_trash_purge\.failed/);
});

test('snapshot import post-import reseed diagnostics persist instead of writing stderr', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/data/snapshot/import.rs'),
    'utf8',
  );
  // Post-#3277 the runtime module moved from `sync_runtime` to
  // `sync::runtime` (folder split). The contract still asserts the
  // explicit cancellation-then-reseed lifecycle, just on the new path.
  const reseedBlock = source.match(
    /if crate::commands::sync::runtime::is_sync_cancelled_for\([\s\S]*?seed_full_sync_internal\(&conn\)[\s\S]*?\n\s*\}/,
  );

  assert.ok(reseedBlock, 'snapshot import must keep an explicit post-import reseed branch');
  assert.doesNotMatch(
    reseedBlock[0],
    /eprintln!\s*\(/,
    'snapshot import reseed diagnostics must not write stderr directly',
  );
  assert.match(source, /snapshot_import\.post_import_reseed\.cancelled/);
  assert.match(source, /snapshot_import\.post_import_reseed\.failed/);
});
