import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const DIRECT_OUTPUT_PATTERN =
  /\b(?:eprintln|println|eprint|print|dbg)!\s*\(|\bstd::io::(?:stdout|stderr)\s*\(/;

const PROXY_ENV_PATH = 'app/src-tauri/src/proxy_env/mod.rs';

test('proxy-env diagnostics persist instead of writing stdout or stderr', () => {
  const source = fs.readFileSync(path.join(repoRoot, PROXY_ENV_PATH), 'utf8');

  assert.doesNotMatch(
    source,
    DIRECT_OUTPUT_PATTERN,
    `${PROXY_ENV_PATH} must use structured diagnostics instead of printing directly`,
  );
  assert.match(source, /append_error_log_internal/);
  assert.match(source, /"proxy_env"/);
  assert.match(source, /report_malformed_proxy_env_with/);

  for (const envName of ['ALL_PROXY', 'HTTPS_PROXY', 'HTTP_PROXY']) {
    assert.match(
      source,
      new RegExp(`report_malformed_proxy_env\\("${envName}"`, 'g'),
      `${PROXY_ENV_PATH} must route malformed ${envName} branches through structured diagnostics`,
    );
  }
});
