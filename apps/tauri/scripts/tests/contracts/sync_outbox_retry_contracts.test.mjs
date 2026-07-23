import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function extractNumericConst(source, name, pattern) {
  const match = source.match(pattern);
  assert.ok(match, `Expected ${name} constant`);
  return Number(match[1]);
}

test('frontend sync outbox quarantine threshold stays aligned with Rust MAX_RETRIES', () => {
  const rustSource = [
    'lorvex-sync/src/outbox/mod.rs',
    'lorvex-sync/src/outbox/constants.rs',
  ]
    .map((relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'))
    .join('\n');
  const tsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/ipc/sync.ts'),
    'utf8',
  );

  const rustMaxRetries = extractNumericConst(
    rustSource,
    'MAX_RETRIES',
    /pub const MAX_RETRIES:\s*i64\s*=\s*(\d+);/,
  );
  const tsMaxRetries = extractNumericConst(
    tsSource,
    'SYNC_OUTBOX_MAX_RETRIES',
    /export const SYNC_OUTBOX_MAX_RETRIES\s*=\s*(\d+);/,
  );

  assert.equal(tsMaxRetries, rustMaxRetries);
});
