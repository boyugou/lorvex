import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bwriteln!\s*\(\s*(?:std::io::)?(?:stdout|stderr)\s*\(|\bstd::io::(?:stdout|stderr)\s*\(|\buse\s+std::io::\{[^}]*\b(?:stdout|stderr)\b/;

const CLI_STARTUP_PATH = 'lorvex-cli/src/startup_maintenance/mod.rs';

test('CLI startup maintenance diagnostics persist instead of writing stdout or stderr', () => {
  const source = fs.readFileSync(path.join(repoRoot, CLI_STARTUP_PATH), 'utf8');

  assert.doesNotMatch(
    source,
    DIRECT_OUTPUT_PATTERN,
    `${CLI_STARTUP_PATH} must persist startup diagnostics instead of writing direct output`,
  );
  assert.match(source, /record_startup_warning/);
  assert.match(source, /record_startup_info/);
  assert.match(source, /cli\.startup\.pending_queue_retention_failed/);
  assert.match(source, /cli\.startup\.trash_purge_deleted/);
});
