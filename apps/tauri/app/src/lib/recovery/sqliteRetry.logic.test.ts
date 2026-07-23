import { describe, expect, it } from 'vitest';

import {
  SQLITE_BUSY_RETRY_BASE_DELAYS_MS,
  SQLITE_BUSY_RETRY_JITTER_FRACTION,
  computeJitteredBusyRetryDelay,
  isRetryableSqliteBusyMessage,
} from './sqliteRetry.logic';

describe('SQLITE_BUSY_RETRY_BASE_DELAYS_MS', () => {
  it('starts at zero so the first attempt has no warm-up cost', () => {
    expect(SQLITE_BUSY_RETRY_BASE_DELAYS_MS[0]).toBe(0);
  });

  it('grows monotonically and is bounded above by ~1.6s per attempt', () => {
    for (let i = 1; i < SQLITE_BUSY_RETRY_BASE_DELAYS_MS.length; i += 1) {
      expect(SQLITE_BUSY_RETRY_BASE_DELAYS_MS[i]!).toBeGreaterThanOrEqual(
        SQLITE_BUSY_RETRY_BASE_DELAYS_MS[i - 1]!,
      );
    }
    expect(SQLITE_BUSY_RETRY_BASE_DELAYS_MS.at(-1)).toBe(1600);
  });
});

describe('computeJitteredBusyRetryDelay', () => {
  it('returns 0 when the base delay is 0', () => {
    expect(computeJitteredBusyRetryDelay(0, 0)).toBe(0);
    expect(computeJitteredBusyRetryDelay(0, 0.99)).toBe(0);
  });

  it('returns 0 when the base delay is negative (defensive)', () => {
    expect(computeJitteredBusyRetryDelay(-50, 0.5)).toBe(0);
  });

  it('returns the base delay when jitter is centered (random=0.5)', () => {
    expect(computeJitteredBusyRetryDelay(100, 0.5)).toBe(100);
  });

  it('reaches the lower jitter bound at random=0', () => {
    const base = 100;
    const min = base * (1 - SQLITE_BUSY_RETRY_JITTER_FRACTION);
    expect(computeJitteredBusyRetryDelay(base, 0)).toBeCloseTo(min);
  });

  it('reaches the upper jitter bound at random=1', () => {
    const base = 100;
    const max = base * (1 + SQLITE_BUSY_RETRY_JITTER_FRACTION);
    expect(computeJitteredBusyRetryDelay(base, 1)).toBeCloseTo(max);
  });

  it('keeps the result within the documented +/- 20% jitter window', () => {
    // Property-style sweep: every random sample must land in the bounded
    // window around the base delay, never overshoot.
    for (const base of SQLITE_BUSY_RETRY_BASE_DELAYS_MS) {
      if (base === 0) continue;
      for (let r = 0; r <= 1; r += 0.1) {
        const delay = computeJitteredBusyRetryDelay(base, r);
        expect(delay).toBeGreaterThanOrEqual(base * (1 - SQLITE_BUSY_RETRY_JITTER_FRACTION) - 1e-9);
        expect(delay).toBeLessThanOrEqual(base * (1 + SQLITE_BUSY_RETRY_JITTER_FRACTION) + 1e-9);
      }
    }
  });
});

describe('isRetryableSqliteBusyMessage', () => {
  it.each([
    'database is locked',
    'Database is Locked',
    'database busy: try again',
    'rusqlite::Error: SQL_BUSY',
    'sqlite returned SQL_BUSY at txn commit',
  ])('classifies %p as retryable', (msg) => {
    expect(isRetryableSqliteBusyMessage(msg)).toBe(true);
  });

  it.each([
    'no such table: tasks',
    'unique constraint violation',
    'connection refused',
    '',
  ])('does not classify %p as retryable', (msg) => {
    expect(isRetryableSqliteBusyMessage(msg)).toBe(false);
  });
});
