import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bwriteln!\s*\(\s*(?:std::io::)?(?:stdout|stderr)\s*\(|\bstd::io::(?:stdout|stderr)\s*\(|\buse\s+std::io::\{[^}]*\b(?:stdout|stderr)\b/;

const STORE_CONNECTION_PATH = 'lorvex-store/src/connection/mod.rs';

test('lorvex-store connection code does not write stdout or stderr directly', () => {
  const source = fs.readFileSync(path.join(repoRoot, STORE_CONNECTION_PATH), 'utf8');

  assert.doesNotMatch(
    source,
    DIRECT_OUTPUT_PATTERN,
    `${STORE_CONNECTION_PATH} must return structured errors instead of writing direct output`,
  );
  assert.match(source, /pub fn open_db\(\) -> Result<Connection, OpenError>/);
  assert.match(source, /open_db_at_path\(&location\.resolved_path\)/);
});
