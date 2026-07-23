import { describe, expect, it } from 'vitest';

import {
  convertWallTimeBetweenTimezones,
  isoFromWallTimeInTimezone,
  offsetMinutesAt,
} from './timezoneMath';

describe('timezoneMath', () => {
  it('probes UTC offsets without relying on localized timezone names', () => {
    expect(offsetMinutesAt(Date.parse('2026-04-15T12:00:00Z'), 'America/New_York')).toBe(-240);
    expect(offsetMinutesAt(Date.parse('2026-01-15T12:00:00Z'), 'America/New_York')).toBe(-300);
    expect(offsetMinutesAt(Date.parse('2026-04-15T12:00:00Z'), 'Asia/Kolkata')).toBe(330);
  });

  it('maps spring-forward gaps to the DST summer interpretation', () => {
    expect(isoFromWallTimeInTimezone('2026-03-08T02:30', 'America/New_York')).toBe(
      '2026-03-08T06:30:00.000Z',
    );
  });

  it('maps fall-back overlaps to the first occurrence', () => {
    expect(isoFromWallTimeInTimezone('2026-11-01T01:30', 'America/New_York')).toBe(
      '2026-11-01T05:30:00.000Z',
    );
  });

  it('converts wall time across zones through the shared UTC resolution path', () => {
    expect(
      convertWallTimeBetweenTimezones(
        { date: '2026-03-08', time: '02:30' },
        'America/New_York',
        'Europe/London',
      ),
    ).toEqual({ date: '2026-03-08', time: '06:30' });
  });

  it('returns null for malformed wall time input', () => {
    expect(isoFromWallTimeInTimezone('not-a-datetime', 'America/New_York')).toBeNull();
    expect(
      convertWallTimeBetweenTimezones(
        { date: '2026-03-08', time: 'bad' },
        'America/New_York',
        'Europe/London',
      ),
    ).toBeNull();
  });
});
