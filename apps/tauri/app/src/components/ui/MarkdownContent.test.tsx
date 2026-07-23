import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

import enLocale from '@/locales/en.json';
import strictParityLocales from '@/locales/strict-parity.json';

import MarkdownContent from './MarkdownContent';

const markdownTaskListKeys = {
  completed: 'markdown.taskList.completedPrefix',
  incomplete: 'markdown.taskList.incompletePrefix',
} as const;
const strictNonSourceLocales = strictParityLocales.filter((locale) => locale !== 'en');

async function loadStrictLocale(locale: string): Promise<Record<string, string>> {
  return (await import(`@/locales/${locale}.json`)).default as Record<string, string>;
}

const i18nMock = vi.hoisted(() => ({
  translations: {
    'markdown.taskList.completedPrefix': 'Completed task: ',
    'markdown.taskList.incompletePrefix': 'Incomplete task: ',
  } as Record<string, string>,
}));

vi.mock('@tauri-apps/plugin-opener', () => ({
  openUrl: vi.fn(),
}));

vi.mock('@/lib/errors/errorLogging', () => ({
  reportClientError: vi.fn(),
}));

vi.mock('@/lib/i18n', () => ({
  useI18n: () => ({
    t: (key: string) => i18nMock.translations[key] ?? key,
  }),
}));

describe('MarkdownContent task-list accessibility', () => {
  it('defines localized task-list screen-reader prefixes', async () => {
    expect(enLocale[markdownTaskListKeys.completed]).toBe('Completed task: ');
    expect(enLocale[markdownTaskListKeys.incomplete]).toBe('Incomplete task: ');
    expect(strictNonSourceLocales.length).toBeGreaterThan(0);

    for (const locale of strictNonSourceLocales) {
      const catalog = await loadStrictLocale(locale);
      expect(catalog[markdownTaskListKeys.completed]?.trim().length, locale).toBeGreaterThan(0);
      expect(catalog[markdownTaskListKeys.incomplete]?.trim().length, locale).toBeGreaterThan(0);
      expect(catalog[markdownTaskListKeys.completed], locale).not.toBe(enLocale[markdownTaskListKeys.completed]);
      expect(catalog[markdownTaskListKeys.incomplete], locale).not.toBe(enLocale[markdownTaskListKeys.incomplete]);
    }
  });

  it('associates rendered task-list checkbox state with item text', () => {
    const html = renderToStaticMarkup(
      <MarkdownContent content={'- [x] Review release notes\n- [ ] Write migration summary'} />,
    );

    expect(html).toContain('class="task-list-item"');
    expect(html).toContain('<span class="sr-only">Completed task: </span>');
    expect(html).toContain('Review release notes');
    expect(html).toContain('<span class="sr-only">Incomplete task: </span>');
    expect(html).toContain('Write migration summary');
  });

  it('renders task-list checkbox state prefixes from the active locale', () => {
    i18nMock.translations = {
      'markdown.taskList.completedPrefix': '已完成任务：',
      'markdown.taskList.incompletePrefix': '未完成任务：',
    };

    const html = renderToStaticMarkup(
      <MarkdownContent content={'- [x] Review release notes\n- [ ] Write migration summary'} />,
    );

    expect(html).toContain('<span class="sr-only">已完成任务：</span>');
    expect(html).toContain('Review release notes');
    expect(html).toContain('<span class="sr-only">未完成任务：</span>');
    expect(html).toContain('Write migration summary');
  });

  it('keeps GFM checkbox inputs visual-only and out of the tab order', () => {
    const html = renderToStaticMarkup(
      <MarkdownContent content={'- [x] Checked\n- [ ] Unchecked'} />,
    );

    expect(html.match(/aria-hidden="true"/g)).toHaveLength(2);
    expect(html.match(/tabindex="-1"/g)).toHaveLength(2);
    expect(html).toContain('type="checkbox"');
  });
});
