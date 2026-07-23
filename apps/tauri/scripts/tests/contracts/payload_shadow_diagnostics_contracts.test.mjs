import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bstd::io::(?:stdout|stderr)\s*\(/;

const PAYLOAD_SHADOW_CRUD_PATH = 'lorvex-sync-payload/src/payload_shadow/crud.rs';

test('payload-shadow CRUD diagnostics persist instead of writing stdout or stderr', () => {
  const source = fs.readFileSync(path.join(repoRoot, PAYLOAD_SHADOW_CRUD_PATH), 'utf8');

  assert.doesNotMatch(
    source,
    DIRECT_OUTPUT_PATTERN,
    `${PAYLOAD_SHADOW_CRUD_PATH} must use structured diagnostics instead of printing directly`,
  );
  assert.match(source, /append_error_log_best_effort/);
  assert.match(source, /"store\.payload_shadow\.corrupted_base_version"/);
  assert.match(source, /corrupted base_version on persisted payload shadow/);
});
