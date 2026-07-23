import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const RUNTIME_PATH = 'app/src/lib/sync/runtime.ts';

function readRuntimeSource() {
  return fs.readFileSync(path.join(repoRoot, RUNTIME_PATH), 'utf8');
}

test('background sync runtime uses structured diagnostics instead of direct console output', () => {
  const source = readRuntimeSource();

  assert.doesNotMatch(
    source,
    /\bconsole\.(?:warn|error)\s*\(/,
    `${RUNTIME_PATH} must not write background sync diagnostics directly to console`,
  );
  assert.match(
    source,
    /reportClientError\(\s*'sync\.background_loop',\s*'Background sync tick failed'/,
    'background sync tick failures must persist through reportClientError',
  );
});

test('background sync repeated-failure toast errors persist as warn-level diagnostics', () => {
  const source = readRuntimeSource();

  assert.match(
    source,
    /reportClientError\(\s*'sync\.repeated_failure_toast',\s*'Failed to show repeated-failure toast',\s*e,\s*undefined,\s*'warn',?\s*\)/s,
    'repeated-failure toast errors must persist through reportClientError at warn level',
  );
});
