import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bwriteln!\s*\(\s*(?:std::io::)?(?:stdout|stderr)\s*\(|\bstd::io::(?:stdout|stderr)\s*\(|\buse\s+std::io::\{[^}]*\b(?:stdout|stderr)\b/;

const FILESYSTEM_BRIDGE_DIAGNOSTIC_PATHS = [
  'app/src-tauri/src/commands/sync/filesystem_bridge/collection.rs',
  'app/src-tauri/src/commands/sync/filesystem_bridge/runtime/orchestration.rs',
  'app/src-tauri/src/commands/sync/filesystem_bridge/runtime/finalize.rs',
  'app/src-tauri/src/commands/sync/filesystem_bridge/runtime/command.rs',
];

test('filesystem-bridge runtime diagnostics persist instead of writing stdout or stderr', () => {
  for (const sourcePath of FILESYSTEM_BRIDGE_DIAGNOSTIC_PATHS) {
    const source = fs.readFileSync(path.join(repoRoot, sourcePath), 'utf8');

    assert.doesNotMatch(
      source,
      DIRECT_OUTPUT_PATTERN,
      `${sourcePath} must route runtime diagnostics through error_logs or structured state`,
    );
  }
});

test('filesystem-bridge sync-owner guard installs a structured release panic hook', () => {
  const sourcePath = 'app/src-tauri/src/commands/sync/filesystem_bridge/runtime/command.rs';
  const source = fs.readFileSync(path.join(repoRoot, sourcePath), 'utf8');

  assert.doesNotMatch(
    source,
    /try_acquire_sync_owner_with_guard_now\([\s\S]*?,\s*None,\s*\)/,
    `${sourcePath} must not opt into the runtime sync-owner stderr fallback hook`,
  );
  assert.match(source, /ReleasePanicHook/);
  assert.match(source, /sync\.filesystem_bridge\.runtime\.lease_release_panic/);
});
