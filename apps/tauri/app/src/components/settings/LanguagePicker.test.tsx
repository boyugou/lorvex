import type { ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const languagePickerRenderState = vi.hoisted(() => ({
  stateCallIndex: 0,
}));

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  return {
    ...actual,
    useState: vi.fn((initialValue: unknown) => {
      languagePickerRenderState.stateCallIndex += 1;
      if (languagePickerRenderState.stateCallIndex === 1) return [true, vi.fn()];
      if (languagePickerRenderState.stateCallIndex === 2) return ['', vi.fn()];
      if (languagePickerRenderState.stateCallIndex === 3) return [{ top: 12, left: 24 }, vi.fn()];
      if (languagePickerRenderState.stateCallIndex === 4) return [0, vi.fn()];
      if (languagePickerRenderState.stateCallIndex === 5) return [true, vi.fn()];
      const value = typeof initialValue === 'function'
        ? (initialValue as () => unknown)()
        : initialValue;
      return [value, vi.fn()];
    }),
  };
});

vi.mock('react-dom', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-dom')>();
  return {
    ...actual,
    createPortal: (node: ReactNode) => node,
  };
});

vi.mock('@/lib/i18n', () => ({
  LANGUAGE_OPTIONS: [
    { label: 'English', value: 'en' },
    { label: 'Chinese', value: 'zh' },
  ],
  useI18n: () => ({
    t: (key: string) => ({
      'common.noResults': 'No results',
      'settings.language': 'Language',
      'settings.languageSearch': 'Search language',
      'settings.useSystem': 'Use system',
    })[key] ?? key,
  }),
}));

import { LanguagePicker } from './LanguagePicker';

describe('LanguagePicker search combobox semantics', () => {
  beforeEach(() => {
    languagePickerRenderState.stateCallIndex = 0;
    vi.stubGlobal('document', { body: {} });
  });

  it('exposes the open language search input as a combobox tied to its listbox', () => {
    const html = renderToStaticMarkup(
      <LanguagePicker
        value="en"
        usingSystem={false}
        onChange={vi.fn()}
        onUseSystem={vi.fn()}
      />,
    );

    const controls = html.match(/role="combobox"[^>]*aria-controls="([^"]+)"/)?.[1];
    expect(controls).toBeTruthy();
    expect(html).toContain('aria-autocomplete="list"');
    expect(html).toContain('aria-expanded="true"');
    expect(html).toContain(`role="listbox" aria-orientation="vertical" aria-label="Language" aria-activedescendant`);
    expect(html).toContain(`id="${controls}"`);
    expect(html).toContain('aria-activedescendant=');
  });
});
