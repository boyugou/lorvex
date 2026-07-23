import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

import type { TranslationKey } from '@/lib/i18n';
import type { ListWithCount } from '@/lib/ipc/tasks/models';
import FooterBar from './FooterBar';

const lists: ListWithCount[] = [
  {
    id: 'list-main',
    name: 'Very long mobile planning list name that should keep truncating inside the picker',
    icon: null,
    color: null,
    description: null,
    ai_notes: null,
    created_at: '2026-05-08T00:00:00.000Z',
    updated_at: '2026-05-08T00:00:00.000Z',
    open_count: 3,
  },
];

const t = ((key: TranslationKey) => key) as Parameters<typeof FooterBar>[0]['t'];

describe('FooterBar mobile layout', () => {
  it('lets picker, date, and actions wrap without forcing a single row', () => {
    const html = renderToStaticMarkup(
      <FooterBar
        lists={lists}
        selectedListId="list-main"
        setSelectedListId={vi.fn()}
        listRequiredHint={null}
        activeDateLabel="A very long detected date label"
        canSubmit
        submitting={false}
        onSubmit={vi.fn()}
        onSubmitAndContinue={vi.fn()}
        isMobile
        t={t}
      />,
    );

    expect(html).toContain('flex flex-wrap items-center gap-2');
    expect(html).toContain('min-w-0 flex-[1_1_12rem] max-w-full');
    expect(html).toContain('w-full justify-end');
  });
});

describe('FooterBar secondary submit accessibility', () => {
  it('names save-and-add-another by action and hides the visual shortcut glyph', () => {
    const html = renderToStaticMarkup(
      <FooterBar
        lists={lists}
        selectedListId="list-main"
        setSelectedListId={vi.fn()}
        listRequiredHint={null}
        activeDateLabel={null}
        canSubmit
        submitting={false}
        onSubmit={vi.fn()}
        onSubmitAndContinue={vi.fn()}
        isMobile={false}
        t={t}
      />,
    );

    expect(html).toContain('aria-label="capture.saveAndAddAnother"');
    expect(html).toContain('aria-keyshortcuts="Shift+Meta+Enter Shift+Control+Enter"');
    expect(html).toContain('<span aria-hidden="true">⇧⌘⏎</span>');
  });
});
