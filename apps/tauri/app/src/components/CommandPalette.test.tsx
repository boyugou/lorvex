import type { ReactNode } from 'react';
import { describe, expect, it, vi } from 'vitest';

type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const { renderToStaticMarkup } = req('react-dom/server') as {
  renderToStaticMarkup: (node: ReactNode) => string;
};

vi.mock('../lib/i18n', () => ({
  useI18n: () => ({
    format: (key: string, vars: Record<string, string>) => `${key}:${vars.count ?? ''}`,
    t: (key: string) => ({
      'common.close': 'Close',
      'common.navigate': 'Navigate',
      'common.noResults': 'No results',
      'common.select': 'Select',
      'palette.a11yNoResults': 'No results',
      'palette.placeholder': 'Search',
      'palette.searching': 'Searching',
      'palette.tipListFilter': 'Type @ for lists',
      'palette.tipSearch': 'Search tasks',
      'palette.tipShortcuts': 'Use shortcuts',
    })[key] ?? key,
  }),
}));

vi.mock('../lib/shortcuts', () => ({
  formatShortcut: (keys: string[]) => keys.join('+'),
}));

vi.mock('@lorvex/shared/types', () => ({
  isTerminalStatus: () => false,
}));

vi.mock('./ui/Modal', () => ({
  Modal: ({ children }: { children: ReactNode }) => <div>{children}</div>,
}));

vi.mock('./command-palette/useCommandPaletteController', () => ({
  useCommandPaletteController: () => ({
    activeOptionId: null,
    activate: vi.fn(),
    clearMoveTask: vi.fn(),
    handleKeyDown: vi.fn(),
    inScopedListMode: false,
    isSearching: false,
    keyedResults: [],
    moveTask: null,
    movingTaskTitle: '',
    optionRefs: { current: new Map() },
    query: 'new inaccessible task',
    results: [],
    selectedScopedList: null,
    selectedTask: null,
    setIsComposing: vi.fn(),
    setQuery: vi.fn(),
    visualSelectedIdx: 0,
  }),
}));

import CommandPalette from './CommandPalette';

describe('CommandPalette no-result listbox semantics', () => {
  it('does not render a native button as a listbox option', () => {
    // The WAI-ARIA constraint we care about is that <button role="option">
    // is the contradictory pair (#4384 kept this guard while moving the
    // no-results panel onto a styled "Create task" CTA button). A button
    // outside the option list — as the empty-state CTA — is fine; what we
    // must not ship is a `<button … role="option">` because JAWS/NVDA
    // double-announce that combination.
    const html = renderToStaticMarkup(
      <CommandPalette
        onClose={() => {}}
        onNavigate={() => {}}
        onQuickCapture={() => {}}
        onSelectTask={() => {}}
      />,
    );

    const resultsStart = html.indexOf('id="command-palette-results"');
    expect(resultsStart).toBeGreaterThanOrEqual(0);
    const resultsHtml = html.slice(resultsStart, html.indexOf('Close', resultsStart));

    expect(resultsHtml).not.toMatch(/<button[^>]*role="option"/);
  });
});
