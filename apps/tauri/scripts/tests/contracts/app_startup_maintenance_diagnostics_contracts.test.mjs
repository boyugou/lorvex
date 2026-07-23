import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bstd::io::(?:stdout|stderr)\s*\(/;

const DB_CONNECTION_PATH = 'app/src-tauri/src/db/connection.rs';

test('app startup maintenance diagnostics persist instead of writing stdout or stderr', () => {
  const source = fs.readFileSync(path.join(repoRoot, DB_CONNECTION_PATH), 'utf8');

  assert.doesNotMatch(
    source,
    DIRECT_OUTPUT_PATTERN,
    `${DB_CONNECTION_PATH} must use structured diagnostics instead of direct output`,
  );
  assert.match(source, /record_startup_warning/);
  assert.match(source, /append_error_log_internal/);
  assert.match(source, /app\.startup\.thread_spawn_failed/);
});
