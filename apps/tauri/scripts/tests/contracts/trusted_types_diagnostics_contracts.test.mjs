import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const TRUSTED_TYPES_PATH = 'app/src/lib/security/trustedTypes.ts';

function readTrustedTypesSource() {
  return fs.readFileSync(path.join(repoRoot, TRUSTED_TYPES_PATH), 'utf8');
}

test('Trusted Types policy setup uses structured diagnostics instead of direct console output', () => {
  const source = readTrustedTypesSource();

  assert.doesNotMatch(
    source,
    /\bconsole\.(?:warn|error)\s*\(/,
    `${TRUSTED_TYPES_PATH} must not write Trusted Types diagnostics directly to console`,
  );
  assert.match(
    source,
    /import\s+\{\s*reportClientError\s*\}\s+from\s+'\.\.\/errors\/errorLogging';/,
    'Trusted Types diagnostics must use the shared frontend diagnostic reporter',
  );
});

test('Trusted Types conflict and registration failures persist as warn-level diagnostics', () => {
  const source = readTrustedTypesSource();

  assert.match(
    source,
    /reportClientError\(\s*'security\.trusted_types',\s*'Trusted Types default policy already registered',\s*undefined,\s*undefined,\s*'warn',?\s*\)/s,
    'pre-existing Trusted Types default policy conflicts must persist as warn-level diagnostics',
  );
  assert.match(
    source,
    /reportClientError\(\s*'security\.trusted_types',\s*'Failed to register Trusted Types default policy',\s*error,\s*undefined,\s*'warn',?\s*\)/s,
    'default Trusted Types policy registration failures must persist as warn-level diagnostics',
  );
  assert.match(
    source,
    /reportClientError\(\s*'security\.trusted_types',\s*'Failed to register named Trusted Types policy',\s*error,\s*undefined,\s*'warn',?\s*\)/s,
    'named Trusted Types policy registration failures must persist as warn-level diagnostics',
  );
});
