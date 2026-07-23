import assert from 'node:assert/strict';
import test from 'node:test';

import { readRustSources } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bwriteln!\s*\(\s*(?:std::io::)?(?:stdout|stderr)\s*\(|\bstd::io::(?:stdout|stderr)\s*\(|\buse\s+std::io::\{[^}]*\b(?:stdout|stderr)\b/;

test('sync apply remote runtime diagnostics persist instead of writing stdout or stderr', () => {
  const source = readRustSources(
    'app/src-tauri/src/commands/sync/runtime/apply/remote.rs',
    'app/src-tauri/src/commands/sync/runtime/apply/remote_core.rs',
    'app/src-tauri/src/commands/sync/runtime/apply/remote_cursors.rs',
    'app/src-tauri/src/commands/sync/runtime/apply/remote_diagnostics.rs',
    'app/src-tauri/src/commands/sync/runtime/apply/remote_events.rs',
    'app/src-tauri/src/commands/sync/runtime/apply/remote_model.rs',
    'app/src-tauri/src/commands/sync/runtime/apply/remote_pending.rs',
    'app/src-tauri/src/commands/sync/runtime/apply/remote_wrappers.rs',
  );

  assert.doesNotMatch(
    source,
    DIRECT_OUTPUT_PATTERN,
    'sync runtime apply/remote sources must route runtime diagnostics through error_logs or structured state',
  );
});
