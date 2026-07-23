import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  detectSystemLocale,
  isValidLocale,
  loadLocale,
  normalizeLocaleCode,
  resolveLocalePreference,
} from '../locales';

afterEach(() => {
  vi.unstubAllGlobals();
});

function stubNavigator(languages: string[], language: string): void {
  vi.stubGlobal('navigator', { languages, language });
}

describe('locale runtime canonicalization', () => {
  it('normalizes supported locale codes without losing registry casing', () => {
    expect(normalizeLocaleCode('zh-Hant')).toBe('zh-Hant');
    expect(normalizeLocaleCode('zh-hant')).toBe('zh-Hant');
    expect(normalizeLocaleCode('zh_Hant')).toBe('zh-Hant');
    expect(normalizeLocaleCode('EN')).toBe('en');
    expect(normalizeLocaleCode('xx')).toBeNull();
  });

  it('keeps isValidLocale strict while preference resolution canonicalizes stored values', () => {
    expect(isValidLocale('zh-Hant')).toBe(true);
    expect(isValidLocale('zh-hant')).toBe(false);
    expect(resolveLocalePreference('"zh-hant"')).toEqual({
      locale: 'zh-Hant',
      usingSystemLocale: false,
    });
  });

  it('detects zh-Hant from lower-case or underscore browser locale tags', () => {
    stubNavigator(['zh-hant-TW'], 'en-US');
    expect(detectSystemLocale()).toBe('zh-Hant');

    stubNavigator(['zh_Hant'], 'en-US');
    expect(detectSystemLocale()).toBe('zh-Hant');
  });

  it('falls back from regional variants to the base locale', () => {
    stubNavigator(['es-MX'], 'en-US');
    expect(detectSystemLocale()).toBe('es');
  });

  it('loads a canonical cache entry for case-insensitive locale input', async () => {
    const translations = await loadLocale('zh-hant');
    expect(Object.keys(translations).length).toBeGreaterThan(0);
  });
});
