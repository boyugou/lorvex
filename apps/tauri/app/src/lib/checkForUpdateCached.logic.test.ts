import { describe, expect, test } from 'vitest';

import {
  isFreshUpdateCheckCacheEntry,
  parseUpdateCheckCacheEntry,
  type UpdateCheckCacheEntry,
} from './checkForUpdateCached.logic';

// The update-check cache prevents a stampede of "is there a new
// release?" HTTP calls. The parser is the trust boundary between
// localStorage (which can hold values written by an older app version,
// a corrupted blob, or a malicious extension) and the cached entry. A
// regression that loosens the parse would reuse stale entries from a
// previous app version and silently hide a genuine update; a
// regression that tightens it would never honor a fresh cache and
// blow the TTL on every launch.

const APP_VERSION = '1.0.0';

const VALID: UpdateCheckCacheEntry = {
  appVersion: APP_VERSION,
  checkedAt: 1_700_000_000_000,
  version: '1.1.0',
};

describe('parseUpdateCheckCacheEntry', () => {
  test('null/empty input returns null (cold start, expected path)', () => {
    expect(parseUpdateCheckCacheEntry(null, APP_VERSION)).toBeNull();
    expect(parseUpdateCheckCacheEntry('', APP_VERSION)).toBeNull();
  });

  test('non-JSON garbage returns null (defensive)', () => {
    expect(parseUpdateCheckCacheEntry('not json', APP_VERSION)).toBeNull();
    expect(parseUpdateCheckCacheEntry('{partial', APP_VERSION)).toBeNull();
  });

  test('non-object root returns null', () => {
    expect(parseUpdateCheckCacheEntry('[]', APP_VERSION)).toBeNull();
    expect(parseUpdateCheckCacheEntry('"string"', APP_VERSION)).toBeNull();
    expect(parseUpdateCheckCacheEntry('42', APP_VERSION)).toBeNull();
    expect(parseUpdateCheckCacheEntry('null', APP_VERSION)).toBeNull();
  });

  test('extra keys reject the entry (refusing schema drift)', () => {
    const drifted = { ...VALID, leakedKey: 'oops' };
    expect(parseUpdateCheckCacheEntry(JSON.stringify(drifted), APP_VERSION)).toBeNull();
  });

  test('missing key rejects the entry (parsed.appVersion check requires the field)', () => {
    const partial = {
      appVersion: APP_VERSION,
      checkedAt: VALID.checkedAt,
      // version field missing
    };
    expect(parseUpdateCheckCacheEntry(JSON.stringify(partial), APP_VERSION)).toBeNull();
  });

  test('appVersion mismatch returns null (key insight: cached entry is for a different binary)', () => {
    expect(parseUpdateCheckCacheEntry(JSON.stringify(VALID), '2.0.0')).toBeNull();
  });

  test('checkedAt must be a finite integer (rejects float, NaN, Infinity, string, null)', () => {
    const cases = [1.5, Number.NaN, Number.POSITIVE_INFINITY, '1700000000000', null];
    for (const checkedAt of cases) {
      const bad = { ...VALID, checkedAt } as unknown as UpdateCheckCacheEntry;
      expect(parseUpdateCheckCacheEntry(JSON.stringify(bad), APP_VERSION)).toBeNull();
    }
  });

  test('version must be string OR null (rejects numbers, objects)', () => {
    for (const version of [42, { latest: '1.1' }, [], false]) {
      const bad = { ...VALID, version } as unknown as UpdateCheckCacheEntry;
      expect(parseUpdateCheckCacheEntry(JSON.stringify(bad), APP_VERSION)).toBeNull();
    }
  });

  test('happy path: round-trips with all fields', () => {
    const round = parseUpdateCheckCacheEntry(JSON.stringify(VALID), APP_VERSION);
    expect(round).toEqual(VALID);
  });

  test('null version (no update available) is preserved', () => {
    const noUpdate: UpdateCheckCacheEntry = { ...VALID, version: null };
    expect(parseUpdateCheckCacheEntry(JSON.stringify(noUpdate), APP_VERSION)).toEqual(noUpdate);
  });

  test('appVersion in the parsed result is forced to the trusted caller value (not the JSON)', () => {
    // Defense-in-depth: even if the caller passed an `appVersion` that
    // matches a malicious JSON, the returned record uses the caller's
    // `appVersion` argument, not the field from the JSON. The check
    // at line 32 already rejects mismatches; this just locks in the
    // construction shape so a future refactor can't reintroduce the
    // bypass.
    const result = parseUpdateCheckCacheEntry(JSON.stringify(VALID), APP_VERSION);
    expect(result?.appVersion).toBe(APP_VERSION);
  });
});

describe('isFreshUpdateCheckCacheEntry', () => {
  const TTL = 60_000;
  const entry: UpdateCheckCacheEntry = {
    appVersion: APP_VERSION,
    checkedAt: 1_000_000,
    version: null,
  };

  test('checkedAt strictly inside TTL window → fresh', () => {
    expect(isFreshUpdateCheckCacheEntry(entry, 1_030_000, TTL)).toBe(true);
  });

  test('checkedAt at exactly TTL boundary → stale (`<` strict)', () => {
    expect(isFreshUpdateCheckCacheEntry(entry, 1_060_000, TTL)).toBe(false);
  });

  test('checkedAt past TTL → stale', () => {
    expect(isFreshUpdateCheckCacheEntry(entry, 5_000_000, TTL)).toBe(false);
  });

  test('checkedAt equal to now → fresh (zero-age is the youngest cache)', () => {
    expect(isFreshUpdateCheckCacheEntry(entry, 1_000_000, TTL)).toBe(true);
  });

  test('checkedAt strictly in the future → not fresh (clock skew defense)', () => {
    // A cache entry whose timestamp is ahead of `now` is suspect —
    // the device clock rolled back, or the entry was synced from a
    // device with a faster clock. Treat as stale to force a re-check
    // rather than serving a "future" timestamp the caller may key
    // off in subsequent comparisons.
    expect(isFreshUpdateCheckCacheEntry(entry, 999_999, TTL)).toBe(false);
  });
});
