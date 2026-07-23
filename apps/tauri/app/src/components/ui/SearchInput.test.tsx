import type { ReactNode } from 'react';
import { describe, expect, it, vi } from 'vitest';

type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const { renderToStaticMarkup } = req('react-dom/server') as {
  renderToStaticMarkup: (node: ReactNode) => string;
};

const runtime = vi.hoisted(() => ({
  runtimeClass: 'desktop' as 'desktop' | 'mobile',
}));

vi.mock('@/lib/i18n', () => ({
  useI18n: () => ({
    t: (key: string) => ({ 'common.clear': 'Clear' })[key] ?? key,
  }),
}));

vi.mock('@/lib/useRuntimeProfile', () => ({
  useRuntimeProfile: () => ({
    runtimeClass: runtime.runtimeClass,
  }),
}));

import { SearchInput } from './SearchInput';

function renderSearchInput(value: string) {
  return renderToStaticMarkup(
    <SearchInput value={value} onChange={() => {}} placeholder="Search tasks" />,
  );
}

describe('SearchInput clear-button spacing (#4285)', () => {
  it('reserves desktop inline-end space for the custom clear button when populated', () => {
    runtime.runtimeClass = 'desktop';

    const html = renderSearchInput('supercalifragilisticexpialidocious-query');

    expect(html).toContain('pe-10');
    expect(html).toContain('[&amp;::-webkit-search-cancel-button]:appearance-none');
    expect(html).toContain('aria-label="Clear"');
  });

  it('reserves the larger mobile hit-target width when populated', () => {
    runtime.runtimeClass = 'mobile';

    const html = renderSearchInput('supercalifragilisticexpialidocious-query');

    expect(html).toContain('pe-14');
    expect(html).toContain('min-h-11 min-w-11');
  });

  it('does not reserve clear-button space when empty', () => {
    runtime.runtimeClass = 'desktop';

    const html = renderSearchInput('');

    expect(html).not.toContain('pe-10');
    expect(html).not.toContain('pe-14');
    expect(html).not.toContain('aria-label="Clear"');
  });
});
