import type { ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const tagFilterPillsRenderState = vi.hoisted(() => ({
  stateCallIndex: 0,
}));

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  return {
    ...actual,
    useState: vi.fn((initialValue: unknown) => {
      tagFilterPillsRenderState.stateCallIndex += 1;
      if (tagFilterPillsRenderState.stateCallIndex === 1) return [true, vi.fn()];
      if (tagFilterPillsRenderState.stateCallIndex === 2) return ['', vi.fn()];
      if (tagFilterPillsRenderState.stateCallIndex === 3) return [{ top: 12, left: 24 }, vi.fn()];
      if (tagFilterPillsRenderState.stateCallIndex === 4) return [0, vi.fn()];
      if (tagFilterPillsRenderState.stateCallIndex === 5) return [true, vi.fn()];
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
  useI18n: () => ({
    t: (key: string) => ({
      'allTasks.clearTagFilter': 'Clear tag filter',
      'allTasks.filterByTag': 'Tags:',
      'common.noResults': 'No results',
      'tags.searchPlaceholder': 'Search tags',
      'tags.selected': 'selected',
    })[key] ?? key,
  }),
}));

import { TagFilterPills } from './TagFilterPills';

describe('TagFilterPills search combobox semantics', () => {
  beforeEach(() => {
    tagFilterPillsRenderState.stateCallIndex = 0;
    vi.stubGlobal('document', { body: {} });
  });

  it('exposes the open tag search input as a combobox tied to its listbox', () => {
    const html = renderToStaticMarkup(
      <TagFilterPills
        tags={['work', 'home']}
        selected={new Set()}
        onToggle={vi.fn()}
        onClear={vi.fn()}
      />,
    );

    const controls = html.match(/role="combobox"[^>]*aria-controls="([^"]+)"/)?.[1];
    expect(controls).toBeTruthy();
    expect(html).toContain('aria-autocomplete="list"');
    expect(html).toContain('aria-expanded="true"');
    expect(html).toContain(`role="listbox" aria-orientation="vertical" id="${controls}"`);
    expect(html).toContain('aria-activedescendant=');
  });

  it('keeps selected long tag chips bounded while preserving the full tag', () => {
    const longTag = 'project-alpha-'.repeat(8);
    const html = renderToStaticMarkup(
      <TagFilterPills
        tags={[longTag]}
        selected={new Set([longTag])}
        onToggle={vi.fn()}
        onClear={vi.fn()}
      />,
    );

    expect(html).toContain(`title="${longTag}"`);
    expect(html).toContain('max-w-[min(14rem,100%)]');
    expect(html).toContain('class="min-w-0 truncate"');
    expect(html).toContain(`aria-label="Clear tag filter: ${longTag}"`);
  });
});
