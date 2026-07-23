import type { ReactNode } from 'react';
import { describe, expect, it, vi } from 'vitest';

type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const { renderToStaticMarkup } = req('react-dom/server') as {
  renderToStaticMarkup: (node: ReactNode) => string;
};

vi.mock('@/lib/i18n', () => ({
  useI18n: () => ({
    t: (key: string) => ({
      'allTasks.sortBy': 'Sort by',
      'allTasks.sortAsc': 'Sort ascending',
      'allTasks.sortDesc': 'Sort descending',
    })[key] ?? key,
  }),
}));

import { ViewToolbar } from './ViewToolbar';

describe('ViewToolbar sort direction semantics', () => {
  it('renders the sort direction button adjacent to, not inside, the dropdown trigger', () => {
    const html = renderToStaticMarkup(
      <ViewToolbar
        sort={{
          value: 'dueDate',
          options: [
            { value: 'default', label: 'Default' },
            { value: 'dueDate', label: 'Due date' },
          ],
          onChange: () => {},
          direction: 'desc',
          onToggleDirection: () => {},
          hideDirectionFor: 'default',
        }}
      />,
    );

    expect(html.match(/<button\b/g)).toHaveLength(2);
    expect(html).not.toMatch(/<button\b(?:(?!<\/button>).)*<button\b/s);
  });
});
