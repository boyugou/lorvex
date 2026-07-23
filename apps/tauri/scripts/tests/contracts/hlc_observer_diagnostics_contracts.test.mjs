import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('HLC observer diagnostics persist instead of writing stderr', () => {
  const source = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/hlc.rs'), 'utf8');
  const registerBody = source.match(/fn register_local_event_observer\(\) \{[\s\S]*?\n\}/);
  const observeBody = source.match(
    /fn observe_remote_version_in_state\([\s\S]*?\n\}\n\n\/\/\/ Try to get the device ID/,
  );
  const directOutputPattern =
    /\b(?:eprintln|eprint|println|print|dbg)!\s*\(|\b(?:write|writeln)!\s*\(\s*(?:&?\s*mut\s+)?(?:(?:std::io::|io::)?(?:stdout|stderr)\s*\(\s*\)|(?:stdout|stderr))|\b(?:std::io::|io::)?(?:stdout|stderr)\s*\(\s*\)/;

  assert.ok(registerBody, 'register_local_event_observer must remain explicit');
  assert.ok(observeBody, 'observe_remote_version_in_state must remain explicit');
  assert.doesNotMatch(
    registerBody[0],
    directOutputPattern,
    'local HLC observer diagnostics must not write direct output',
  );
  assert.doesNotMatch(
    observeBody[0],
    directOutputPattern,
    'remote HLC observer diagnostics must not write direct output',
  );
  assert.match(source, /hlc\.observer\.state_unavailable/);
  assert.match(source, /hlc\.observer\.malformed_remote_version/);
  assert.match(source, /try_append_error_log_best_effort/);
});
