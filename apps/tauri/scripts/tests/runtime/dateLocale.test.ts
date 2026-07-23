import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  formatRelativeTime,
  localeWeekStartDay,
  localizedWeekdayOptions,
  parseWeekStartDayPreference,
} from '../../../app/src/lib/dates/dateLocale';
import { readBrowserLocale } from '../../../app/src/lib/dates/dateLocale.runtime';

/**
 * Minimal translator stub that returns the same sentinel strings as the real
 * English catalog so assertions can match on exact output. Using the real
 * locale catalog here would require loading the full Vite module graph, which
 * is unnecessary for a pure formatting test.
 */
const tStub = (k: string): string => {
  switch (k) {
    case 'time.justNow': return 'just now';
    case 'time.minutesAgo': return 'm ago';
    case 'time.hoursAgo': return 'h ago';
    case 'time.daysAgo': return 'd ago';
    case 'time.inMinutes': return 'in {value}m';
    case 'time.inHours': return 'in {value}h';
    case 'time.inDays': return 'in {value}d';
    default: return k;
  }
};

// Cast so we can pass the stub without importing the real TranslationKey type.
const t = tStub as unknown as Parameters<typeof formatRelativeTime>[2];
const format = ((k: string, vars: { value: string }): string =>
  tStub(k).replace('{value}', vars.value)) as unknown as Parameters<typeof formatRelativeTime>[3];

function iso(msFromNow: number): string {
  return new Date(Date.now() + msFromNow).toISOString();
}

function withFixedNow<T>(nowMs: number, fn: () => T): T {
  const originalNow = Date.now;
  Date.now = () => nowMs;
  try {
    return fn();
  } finally {
    Date.now = originalNow;
  }
}

function withNavigatorLanguage<T>(language: string, fn: () => T): T {
  const original = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  Object.defineProperty(globalThis, 'navigator', {
    configurable: true,
    value: { language },
  });
  try {
    return fn();
  } finally {
    if (original) {
      Object.defineProperty(globalThis, 'navigator', original);
    } else {
      Reflect.deleteProperty(globalThis, 'navigator');
    }
  }
}

test('date locale runtime reads browser language and falls back for missing or blank values', () => {
  const original = Object.getOwnPropertyDescriptor(globalThis, 'navigator');

  try {
    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: { language: 'fr-CA' },
    });
    assert.equal(readBrowserLocale(), 'fr-CA');

    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: { language: '   ' },
    });
    assert.equal(readBrowserLocale(), 'en-US');

    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: undefined,
    });
    assert.equal(readBrowserLocale(), 'en-US');
  } finally {
    if (original) {
      Object.defineProperty(globalThis, 'navigator', original);
    } else {
      Reflect.deleteProperty(globalThis, 'navigator');
    }
  }
});

test('date locale module delegates browser locale reads to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/dates/dateLocale.ts'),
    'utf8',
  );

  assert.match(source, /import \{ readBrowserLocale \} from '\.\/dateLocale\.runtime';/);
  assert.doesNotMatch(source, /\bnavigator\b/);
  assert.doesNotMatch(source, /JSON\.parse\(raw\)/);
});

test('localeWeekStartDay respects Intl weekInfo for Sunday, Monday, and Saturday locales', () => {
  const OriginalLocale = Intl.Locale;
  class FakeLocale {
    readonly language: string;

    constructor(language: string) {
      this.language = language;
    }

    getWeekInfo() {
      if (this.language === 'en-US') return { firstDay: 7 };
      if (this.language === 'fa-IR') return { firstDay: 6 };
      return { firstDay: 1 };
    }
  }

  Object.defineProperty(Intl, 'Locale', {
    configurable: true,
    value: FakeLocale,
  });

  try {
    assert.equal(withNavigatorLanguage('en-US', () => localeWeekStartDay()), 0);
    assert.equal(withNavigatorLanguage('de-DE', () => localeWeekStartDay()), 1);
    assert.equal(withNavigatorLanguage('fa-IR', () => localeWeekStartDay()), 6);
  } finally {
    Object.defineProperty(Intl, 'Locale', {
      configurable: true,
      value: OriginalLocale,
    });
  }
});

test('localeWeekStartDay fallback extracts region subtags correctly and keeps AE as Monday-start', () => {
  const OriginalLocale = Intl.Locale;
  class BrokenLocale {
    constructor(_language: string) {}
  }

  Object.defineProperty(Intl, 'Locale', {
    configurable: true,
    value: BrokenLocale,
  });

  try {
    assert.equal(withNavigatorLanguage('zh-Hant-TW', () => localeWeekStartDay()), 0);
    assert.equal(withNavigatorLanguage('uz-Arab-AF', () => localeWeekStartDay()), 6);
    assert.equal(withNavigatorLanguage('ar-AE', () => localeWeekStartDay()), 1);
  } finally {
    Object.defineProperty(Intl, 'Locale', {
      configurable: true,
      value: OriginalLocale,
    });
  }
});

test('parseWeekStartDayPreference accepts only integer day indices in [0, 6]', () => {
  assert.equal(parseWeekStartDayPreference(null, 1), 1);
  assert.equal(parseWeekStartDayPreference('0', 1), 0);
  assert.equal(parseWeekStartDayPreference('6', 1), 6);
  assert.equal(parseWeekStartDayPreference('7', 1), 1);
  assert.equal(parseWeekStartDayPreference('"1"', 0), 0);
  assert.equal(parseWeekStartDayPreference('1.0', 0), 0);
  assert.equal(parseWeekStartDayPreference('1.5', 0), 0);
  assert.equal(parseWeekStartDayPreference('1e0', 0), 0);
});

test('localizedWeekdayOptions rotates labels to the requested start day while preserving day indices', () => {
  const sundayFirst = localizedWeekdayOptions('en-US', 0, 'short');
  const saturdayFirst = localizedWeekdayOptions('en-US', 6, 'short');

  assert.equal(sundayFirst.length, 7);
  assert.deepEqual(sundayFirst.map((option) => option.dayIndex), [0, 1, 2, 3, 4, 5, 6]);
  assert.deepEqual(saturdayFirst.map((option) => option.dayIndex), [6, 0, 1, 2, 3, 4, 5]);
  assert.equal(sundayFirst[0]?.label, 'Sun');
  assert.equal(saturdayFirst[0]?.label, 'Sat');
});

test('localizedWeekdayOptions fails closed for invalid start-day inputs', () => {
  assert.deepEqual(
    localizedWeekdayOptions('en-US', -1, 'short').map((option) => option.dayIndex),
    [0, 1, 2, 3, 4, 5, 6],
  );
  assert.deepEqual(
    localizedWeekdayOptions('en-US', 7, 'short').map((option) => option.dayIndex),
    [0, 1, 2, 3, 4, 5, 6],
  );
  assert.deepEqual(
    localizedWeekdayOptions('en-US', 1.5, 'short').map((option) => option.dayIndex),
    [0, 1, 2, 3, 4, 5, 6],
  );
});

test('formatRelativeTime: renders "just now" for <1min magnitudes (zero diff)', () => {
  withFixedNow(Date.UTC(2026, 0, 1, 12, 0, 0), () => {
    assert.equal(formatRelativeTime(iso(0), 'en', t, format), 'just now');
  });
});

test('formatRelativeTime: renders "just now" for sub-minute past and future', () => {
  withFixedNow(Date.UTC(2026, 0, 1, 12, 0, 0), () => {
    assert.equal(formatRelativeTime(iso(-30_000), 'en', t, format), 'just now');
    assert.equal(formatRelativeTime(iso(30_000), 'en', t, format), 'just now');
  });
});

test('formatRelativeTime: past minutes render with "ago" suffix', () => {
  withFixedNow(Date.UTC(2026, 0, 1, 12, 0, 0), () => {
    assert.equal(formatRelativeTime(iso(-5 * 60_000), 'en', t, format), '5m ago');
  });
});

test('formatRelativeTime: past hours render with "ago" suffix', () => {
  withFixedNow(Date.UTC(2026, 0, 1, 12, 0, 0), () => {
    assert.equal(formatRelativeTime(iso(-3 * 3600_000), 'en', t, format), '3h ago');
  });
});

test('formatRelativeTime: past days render with "ago" suffix', () => {
  withFixedNow(Date.UTC(2026, 0, 1, 12, 0, 0), () => {
    assert.equal(formatRelativeTime(iso(-2 * 86_400_000), 'en', t, format), '2d ago');
  });
});

test('formatRelativeTime: future minutes render with "in X" prefix (not "-Xm ago")', () => {
  withFixedNow(Date.UTC(2026, 0, 1, 12, 0, 0), () => {
    const out = formatRelativeTime(iso(5 * 60_000), 'en', t, format);
    assert.equal(out, 'in 5m');
    assert.ok(!out.includes('-'), 'future strings must never contain a leading minus');
    assert.ok(!out.includes('ago'), 'future strings must never contain "ago"');
  });
});

test('formatRelativeTime: future hours render with "in X" prefix', () => {
  withFixedNow(Date.UTC(2026, 0, 1, 12, 0, 0), () => {
    const out = formatRelativeTime(iso(3 * 3600_000), 'en', t, format);
    assert.equal(out, 'in 3h');
    assert.ok(!out.includes('-'));
    assert.ok(!out.includes('ago'));
  });
});

test('formatRelativeTime: future days render with "in X" prefix', () => {
  withFixedNow(Date.UTC(2026, 0, 1, 12, 0, 0), () => {
    const out = formatRelativeTime(iso(49 * 3600_000), 'en', t, format);
    assert.equal(out, 'in 2d');
    assert.ok(!out.includes('-'));
    assert.ok(!out.includes('ago'));
  });
});

test('formatRelativeTime: >=7d magnitudes fall through to absolute date for past and future', () => {
  withFixedNow(Date.UTC(2026, 0, 1, 12, 0, 0), () => {
    const past = formatRelativeTime(iso(-30 * 86_400_000), 'en', t, format);
    const future = formatRelativeTime(iso(30 * 86_400_000), 'en', t, format);
    assert.ok(!past.includes('ago'), 'absolute past dates should not be "ago"');
    assert.ok(!future.includes('in '), 'absolute future dates should not be "in X"');
    assert.ok(!past.includes('-'));
    assert.ok(!future.includes('-'));
  });
});

test('formatRelativeTime: fallback path still formats numbers with locale digits', () => {
  const original = Intl.RelativeTimeFormat;
  Object.defineProperty(Intl, 'RelativeTimeFormat', {
    configurable: true,
    value: class BrokenRelativeTimeFormat {
      constructor() {
        throw new Error('boom');
      }
    },
  });

  try {
    withFixedNow(Date.UTC(2026, 0, 1, 12, 0, 0), () => {
      const out = formatRelativeTime(iso(5 * 60_000), 'ar-EG', t, format);
      assert.ok(out.includes('\u0665'), 'fallback should preserve locale digits');
      assert.ok(!out.includes('5m'), 'fallback should not regress to ASCII digits');
    });
  } finally {
    Object.defineProperty(Intl, 'RelativeTimeFormat', {
      configurable: true,
      value: original,
    });
  }
});
