import { afterEach, describe, expect, it, vi } from 'vitest';

import { applyBrowserLocaleDocumentAttributes } from './i18nSystemLocale.runtime';

afterEach(() => {
  vi.unstubAllGlobals();
});

function stubDocumentElement(): { lang: string; dir: string } {
  const documentElement = { lang: '', dir: '' };
  vi.stubGlobal('document', { documentElement });
  return documentElement;
}

describe('applyBrowserLocaleDocumentAttributes', () => {
  it('uses locale registry text direction metadata', () => {
    const documentElement = stubDocumentElement();

    applyBrowserLocaleDocumentAttributes('fa');
    expect(documentElement.lang).toBe('fa');
    expect(documentElement.dir).toBe('rtl');

    applyBrowserLocaleDocumentAttributes('zh-Hant');
    expect(documentElement.lang).toBe('zh-Hant');
    expect(documentElement.dir).toBe('ltr');
  });
});
