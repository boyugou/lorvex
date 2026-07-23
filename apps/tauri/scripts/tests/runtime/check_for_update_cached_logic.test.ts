import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  isFreshUpdateCheckCacheEntry,
  parseUpdateCheckCacheEntry,
} from '../../../app/src/lib/checkForUpdateCached.logic';

test('update-check cache: parser accepts a valid same-version entry', () => {
  const entry = parseUpdateCheckCacheEntry(
    JSON.stringify({
      version: '1.2.3',
      checkedAt: 1_700_000_000_000,
      appVersion: '0.9.0',
    }),
    '0.9.0',
  );

  assert.deepEqual(entry, {
    version: '1.2.3',
    checkedAt: 1_700_000_000_000,
    appVersion: '0.9.0',
  });
});

test('update-check cache: parser rejects mismatched appVersion and malformed payloads', () => {
  assert.equal(
    parseUpdateCheckCacheEntry(
      JSON.stringify({ version: '1.2.3', checkedAt: 1_700_000_000_000, appVersion: '0.8.0' }),
      '0.9.0',
    ),
    null,
  );
  assert.equal(parseUpdateCheckCacheEntry('not json', '0.9.0'), null);
  assert.equal(
    parseUpdateCheckCacheEntry(
      JSON.stringify({ version: { major: 1 }, checkedAt: 1_700_000_000_000, appVersion: '0.9.0' }),
      '0.9.0',
    ),
    null,
    'non-string version payloads must not be accepted as a cache hit',
  );
  assert.equal(
    parseUpdateCheckCacheEntry(
      JSON.stringify({ version: null, checkedAt: Number.NaN, appVersion: '0.9.0' }),
      '0.9.0',
    ),
    null,
    'NaN timestamps must not pin the cache forever',
  );
  assert.equal(
    parseUpdateCheckCacheEntry(
      JSON.stringify({ version: '1.2.3', checkedAt: 1_700_000_000_000.5, appVersion: '0.9.0' }),
      '0.9.0',
    ),
    null,
    'fractional timestamps must not be accepted as cache entries',
  );
  assert.equal(
    parseUpdateCheckCacheEntry(
      JSON.stringify({
        version: '1.2.3',
        checkedAt: 1_700_000_000_000,
        appVersion: '0.9.0',
        channel: 'beta',
      }),
      '0.9.0',
    ),
    null,
    'unknown cache fields must fail closed instead of widening the persisted schema',
  );
  assert.equal(
    parseUpdateCheckCacheEntry(
      JSON.stringify({ checkedAt: 1_700_000_000_000, appVersion: '0.9.0' }),
      '0.9.0',
    ),
    null,
    'missing version must fail closed instead of being treated as a cached no-update result',
  );
});

test('update-check cache: freshness rejects future timestamps and expired entries', () => {
  const ttlMs = 6 * 60 * 60 * 1000;
  const now = 1_700_000_000_000;
  const fresh = {
    version: '1.2.3',
    checkedAt: now - 1_000,
    appVersion: '0.9.0',
  };
  const future = {
    version: '1.2.3',
    checkedAt: now + 60_000,
    appVersion: '0.9.0',
  };
  const stale = {
    version: '1.2.3',
    checkedAt: now - ttlMs,
    appVersion: '0.9.0',
  };

  assert.equal(isFreshUpdateCheckCacheEntry(fresh, now, ttlMs), true);
  assert.equal(isFreshUpdateCheckCacheEntry(future, now, ttlMs), false);
  assert.equal(isFreshUpdateCheckCacheEntry(stale, now, ttlMs), false);
});

test('update-check cache parser delegates JSON parsing to the shared helper', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/checkForUpdateCached.logic.ts'),
    'utf8',
  );

  assert.match(source, /from '\.\/security\/jsonParse';/);
  assert.doesNotMatch(source, /JSON\.parse\(/);
});
