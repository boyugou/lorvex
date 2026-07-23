import { describe, expect, it } from 'vitest';

import {
  addYmdDays,
  diffYmdDays,
  isCanonicalYmd,
  parseYmd,
  ymdFromParts,
} from './dayContextMath';

describe('canonical frontend YMD helpers', () => {
  it('accepts only canonical real YYYY-MM-DD dates', () => {
    expect(parseYmd('2026-04-24')).toEqual({ year: 2026, month: 3, day: 24 });
    expect(parseYmd('2028-02-29')).toEqual({ year: 2028, month: 1, day: 29 });
    expect(isCanonicalYmd('2026-04-24')).toBe(true);

    for (const value of [
      '2026-4-24',
      '2026-04-24x',
      '2026-04-31',
      '2027-02-29',
      '0000-01-01',
      '99999-01-01',
      null,
      42,
    ]) {
      expect(parseYmd(value)).toBeNull();
      expect(isCanonicalYmd(value)).toBe(false);
    }
  });

  it('serializes zero-based month parts into canonical YMD strings', () => {
    expect(ymdFromParts(2026, 0, 7)).toBe('2026-01-07');
    expect(ymdFromParts(2026, 11, 31)).toBe('2026-12-31');
  });

  it('adds days across leap days and month/year boundaries with UTC date-only arithmetic', () => {
    expect(addYmdDays('2024-02-28', 1)).toBe('2024-02-29');
    expect(addYmdDays('2023-02-28', 1)).toBe('2023-03-01');
    expect(addYmdDays('2026-01-31', 1)).toBe('2026-02-01');
    expect(addYmdDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addYmdDays('2026-03-08', -7)).toBe('2026-03-01');
  });

  it('computes timezone-insensitive whole-day diffs', () => {
    expect(diffYmdDays('2026-03-07', '2026-03-08')).toBe(1);
    expect(diffYmdDays('2026-03-08', '2026-03-09')).toBe(1);
    expect(diffYmdDays('2026-10-24', '2026-10-25')).toBe(1);
    expect(diffYmdDays('2026-04-22', '2026-04-20')).toBe(-2);
  });

  it('fails closed for invalid day diffs', () => {
    expect(diffYmdDays('2026-02-30', '2026-03-01')).toBe(0);
    expect(diffYmdDays('not-a-date', '2026-03-01')).toBe(0);
    expect(diffYmdDays('2026-03-01', '2026-13-01')).toBe(0);
  });
});
