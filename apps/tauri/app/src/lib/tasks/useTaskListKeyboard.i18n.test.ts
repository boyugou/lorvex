/**
 * Regression test.
 *
 * `useTaskListKeyboard` announces `tasks.bulkSelectHint` to the live
 * region when the user presses a non-selection key while bulk-select
 * mode is active. Pre-fix the string was hardcoded English, which
 * violates CLAUDE.md rule 10 (i18n is mandatory).
 *
 * Lock in:
 *   1. The translation key exists in the source locale and every
 *      configured strict-parity locale (no drift), AND
 *   2. Strict non-source locales actually carry distinct strings, so
 *      we know real translations were supplied (not passthroughs).
 */
import { describe, expect, it } from 'vitest';

import enLocale from '@/locales/en.json';
import strictParityLocales from '@/locales/strict-parity.json';

const KEY = 'tasks.bulkSelectHint' as const;
const strictNonSourceLocales = strictParityLocales.filter((locale) => locale !== 'en');

async function loadStrictLocale(locale: string): Promise<Record<string, string>> {
  return (await import(`@/locales/${locale}.json`)).default as Record<string, string>;
}

describe('useTaskListKeyboard — bulkSelectHint i18n', () => {
  it('exposes the key in en.json with non-empty content', () => {
    const value = enLocale[KEY];
    expect(typeof value).toBe('string');
    expect(value.length).toBeGreaterThan(0);
    // Sanity: pre-fix English string survives so screen-reader
    // semantics don't regress in the default locale.
    expect(value).toMatch(/bulk-select/i);
  });

  it('exposes translated content in every strict non-source locale', async () => {
    expect(strictNonSourceLocales.length).toBeGreaterThan(0);

    for (const locale of strictNonSourceLocales) {
      const catalog = await loadStrictLocale(locale);
      const value = catalog[KEY];
      expect(typeof value, locale).toBe('string');
      if (typeof value !== 'string') {
        throw new Error(`${locale} is missing ${KEY}`);
      }
      expect(value.trim().length, locale).toBeGreaterThan(0);
      expect(value, locale).not.toBe(enLocale[KEY]);
    }
  });
});
