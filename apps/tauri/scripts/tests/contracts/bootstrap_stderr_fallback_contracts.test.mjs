import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

// Post-#3303 the previous monolithic `bootstrap.rs` was split into a
// folder; the production-source contract now spans every non-test file
// under `bootstrap/`. We deliberately exclude `tests.rs` because it
// names the symbols (e.g. `eprintln`) inside string fixtures used by
// regression tests, and we exclude `mod.rs` purely as a defense-in-
// depth measure (it should never carry any real logic).
const BOOTSTRAP_DIR = 'app/src-tauri/src/bootstrap';
const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|eprint|println|print|dbg)!\s*\(|\b(?:std::io::|io::)?(?:stdout|stderr)\s*\(/;

function readProductionBootstrapFiles() {
  const dir = path.join(repoRoot, BOOTSTRAP_DIR);
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  let combined = '';
  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith('.rs')) continue;
    if (entry.name === 'tests.rs') continue;
    combined += `\n// ===== ${entry.name} =====\n`;
    combined += fs.readFileSync(path.join(dir, entry.name), 'utf8');
  }
  return combined;
}

test('bootstrap startup and panic diagnostics avoid direct stderr fallbacks', () => {
  const source = readProductionBootstrapFiles();

  assert.doesNotMatch(
    source,
    DIRECT_OUTPUT_PATTERN,
    'bootstrap startup and panic diagnostics should use marker/error_logs/default hook surfaces instead of direct output',
  );
  assert.match(source, /write_owner_only_marker/);
  assert.match(source, /panic!\s*\(\s*"\{message\}"\s*\)/);
  assert.match(source, /default_hook\(info\)/);
  assert.match(source, /SUPPRESS_DEFAULT_PANIC_HOOK/);
});
