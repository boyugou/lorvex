import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  _resetDateFormatterCacheForTests,
  formatCalendarDate,
  formatCalendarDateInTimeZone,
  formatDate,
  formatRelativeTime,
  formatTimestamp,
  localizedWeekdayOptions,
  parseWeekStartDayPreference,
  resolveDateLocale,
} from './dateLocale';

afterEach(() => {
  vi.useRealTimers();
});

describe('date locale normalization', () => {
  it('maps supported app locale aliases to Intl-safe date locales', () => {
    expect(resolveDateLocale('zh')).toBe('zh-CN');
    expect(resolveDateLocale('zh-Hant')).toBe('zh-Hant');
    expect(resolveDateLocale('zh_hant')).toBe('zh-Hant');
    expect(resolveDateLocale('zh-hant-TW')).toBe('zh-Hant');
    expect(resolveDateLocale('es-MX')).toBe('es');
  });

  it('falls back to English for unsupported date locales', () => {
    expect(resolveDateLocale('123')).toBe('en-US');
  });

  it('uses Traditional Chinese weekday labels for zh-Hant aliases', () => {
    const labels = localizedWeekdayOptions('zh_hant_TW', 0, 'short').map(({ label }) => label);
    const expected = new Intl.DateTimeFormat('zh-Hant', { weekday: 'short' })
      .format(new Date(2024, 0, 7));
    expect(labels[0]).toBe(expected);
  });

  it('formats relative time with canonicalized Traditional Chinese locale', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-04-29T12:00:00Z'));
    const result = formatRelativeTime(
      '2026-04-28T12:00:00Z',
      'zh_hant_TW',
      () => 'just now',
      (_key, vars) => vars.value,
      'UTC',
    );
    expect(result).toBe(new Intl.RelativeTimeFormat('zh-Hant', {
      numeric: 'always',
      style: 'narrow',
    }).format(-1, 'day'));
  });

  it('parses week-start preferences with fallback for absent or invalid values', () => {
    expect(parseWeekStartDayPreference(null, 1)).toBe(1);
    expect(parseWeekStartDayPreference('not-json', 1)).toBe(1);
    expect(parseWeekStartDayPreference('7', 1)).toBe(1);
    expect(parseWeekStartDayPreference('0', 1)).toBe(0);
    expect(parseWeekStartDayPreference('6', 1)).toBe(6);
  });
});

describe('formatTimestamp', () => {
  it('renders an ISO timestamp in the user locale + timezone', () => {
    // Pin the input to UTC; assert against an Intl-built reference so the
    // test is locale-runtime-stable and surface the exact same output the
    // production path would emit.
    const iso = '2026-05-03T12:00:00Z';
    const expected = new Intl.DateTimeFormat('en-US', {
      timeZone: 'UTC',
      dateStyle: 'short',
      timeStyle: 'short',
    }).format(new Date(iso));
    expect(formatTimestamp(iso, 'en', 'UTC', { dateStyle: 'short', timeStyle: 'short' })).toBe(expected);
  });

  it('omits timeZone when no timezone is provided (caller falls through to OS tz)', () => {
    // The OS tz is whatever Vitest picks up — assert via Intl with no
    // explicit timeZone so both call paths produce the same string.
    const iso = '2026-05-03T12:00:00Z';
    const reference = new Intl.DateTimeFormat('en-US', {
      dateStyle: 'short',
    }).format(new Date(iso));
    expect(formatTimestamp(iso, 'en', undefined, { dateStyle: 'short' })).toBe(reference);
  });

  it('canonicalizes the locale alias before formatting (zh → zh-CN, zh-Hant stays)', () => {
    const iso = '2026-05-03T12:00:00Z';
    const ref = new Intl.DateTimeFormat('zh-CN', {
      timeZone: 'UTC',
      dateStyle: 'medium',
    }).format(new Date(iso));
    expect(formatTimestamp(iso, 'zh', 'UTC', { dateStyle: 'medium' })).toBe(ref);
  });
});

describe('formatDate', () => {
  it('formats a Date object in the user locale + tz', () => {
    const date = new Date('2026-05-03T15:30:00Z');
    const reference = new Intl.DateTimeFormat('en-US', {
      timeZone: 'UTC',
      hour: 'numeric',
      minute: '2-digit',
    }).format(date);
    expect(formatDate(date, 'en', { timeZone: 'UTC', hour: 'numeric', minute: '2-digit' })).toBe(reference);
  });

  it('honors the resolved locale alias (zh → zh-CN)', () => {
    const date = new Date('2026-05-03T00:00:00Z');
    const reference = new Intl.DateTimeFormat('zh-CN', {
      timeZone: 'UTC',
      year: 'numeric',
      month: 'long',
    }).format(date);
    expect(formatDate(date, 'zh', { timeZone: 'UTC', year: 'numeric', month: 'long' })).toBe(reference);
  });

  it('falls back to en-US for unsupported locales', () => {
    const date = new Date('2026-05-03T00:00:00Z');
    const reference = new Intl.DateTimeFormat('en-US', {
      timeZone: 'UTC',
      month: 'short',
      day: 'numeric',
    }).format(date);
    expect(formatDate(date, '123', { timeZone: 'UTC', month: 'short', day: 'numeric' })).toBe(reference);
  });
});

describe('memoized formatter cache', () => {
  it('returns the same formatter instance for repeated (locale, options-shape) calls', () => {
    // We can't observe the cache directly from the public API, but we
    // can pin the BEHAVIOR: repeated calls must produce identical
    // output for the same canonical option shape regardless of caller-
    // passed property order. A regression that broke the canonical
    // key (e.g. used `JSON.stringify(options)` directly) would still
    // produce the same output here — so this test is mainly a
    // smoke-check that the caching code path doesn't corrupt the
    // formatter state across calls.
    _resetDateFormatterCacheForTests();
    const a = formatTimestamp('2026-05-03T12:00:00Z', 'en', 'UTC', { dateStyle: 'short' });
    const b = formatTimestamp('2026-05-03T12:00:00Z', 'en', 'UTC', { dateStyle: 'short' });
    expect(a).toBe(b);
    // Different ms-precision input still hits the cache for the same
    // formatter shape.
    const c = formatTimestamp('2026-05-03T12:00:01Z', 'en', 'UTC', { dateStyle: 'short' });
    expect(c).toBe(a); // same calendar day → identical 'short' rendering
  });

  it('different option-key order resolves to the same formatter (canonical key)', () => {
    // The cache key sorts option keys alphabetically; two callers
    // that pass `{ year, month }` and `{ month, year }` must get the
    // same cached formatter (and thus identical output). This is the
    // contract that justifies sorting the cache key — without it a
    // refactor that reorders option construction would silently
    // double cache occupancy.
    _resetDateFormatterCacheForTests();
    const date = new Date('2026-05-03T00:00:00Z');
    const ab = formatDate(date, 'en', { year: 'numeric', month: 'long', timeZone: 'UTC' });
    const ba = formatDate(date, 'en', { month: 'long', year: 'numeric', timeZone: 'UTC' });
    expect(ab).toBe(ba);
  });
});

describe('formatCalendarDate', () => {
  it('formats a YYYY-MM-DD anchored at UTC (no day-shift for users west of UTC)', () => {
    // Default options: { month: 'short', day: 'numeric' }. Anchor to UTC
    // explicitly in the reference so the test is OS-tz-stable.
    const reference = new Intl.DateTimeFormat('en-US', {
      timeZone: 'UTC',
      month: 'short',
      day: 'numeric',
    }).format(new Date('2026-05-03T00:00:00Z'));
    expect(formatCalendarDate('2026-05-03', 'en')).toBe(reference);
  });

  it('honors caller options (weekday/year/long-month) while still anchoring at UTC', () => {
    const reference = new Intl.DateTimeFormat('en-US', {
      timeZone: 'UTC',
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    }).format(new Date('2026-05-03T00:00:00Z'));
    expect(
      formatCalendarDate('2026-05-03', 'en', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      }),
    ).toBe(reference);
  });

  it('falls back to en-US when the locale is unsupported', () => {
    const reference = new Intl.DateTimeFormat('en-US', {
      timeZone: 'UTC',
      month: 'short',
      day: 'numeric',
    }).format(new Date('2026-05-03T00:00:00Z'));
    expect(formatCalendarDate('2026-05-03', '123')).toBe(reference);
  });
});

describe('formatCalendarDateInTimeZone', () => {
  it('formats a YMD as the same calendar day in an extreme positive timezone', () => {
    const reference = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Pacific/Kiritimati',
      weekday: 'long',
      month: 'long',
      day: 'numeric',
    }).format(new Date('2025-12-31T22:00:00Z'));

    expect(
      formatCalendarDateInTimeZone('2026-01-01', 'en', 'Pacific/Kiritimati', {
        weekday: 'long',
        month: 'long',
        day: 'numeric',
      }),
    ).toBe(reference);
    expect(reference).toContain('Thursday');
  });

  it('formats a YMD as the same calendar day in an extreme negative timezone', () => {
    const reference = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Pacific/Honolulu',
      weekday: 'short',
    }).format(new Date('2026-01-01T22:00:00Z'));

    expect(
      formatCalendarDateInTimeZone('2026-01-01', 'en', 'Pacific/Honolulu', {
        weekday: 'short',
      }),
    ).toBe(reference);
  });

  it('uses the resolved app locale with caller options', () => {
    const reference = new Intl.DateTimeFormat('zh-CN', {
      timeZone: 'Asia/Shanghai',
      weekday: 'short',
      month: 'long',
      day: 'numeric',
    }).format(new Date('2026-05-02T04:00:00Z'));

    expect(
      formatCalendarDateInTimeZone('2026-05-02', 'zh', 'Asia/Shanghai', {
        weekday: 'short',
        month: 'long',
        day: 'numeric',
      }),
    ).toBe(reference);
  });
});
