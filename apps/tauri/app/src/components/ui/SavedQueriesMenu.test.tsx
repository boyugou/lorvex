import type { ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const savedQueriesMenuRenderState = vi.hoisted(() => ({
  stateCallIndex: 0,
}));

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  return {
    ...actual,
    useState: vi.fn((initialValue: unknown) => {
      savedQueriesMenuRenderState.stateCallIndex += 1;
      const value = typeof initialValue === 'function'
        ? (initialValue as () => unknown)()
        : initialValue;

      if (savedQueriesMenuRenderState.stateCallIndex === 1) {
        return [true, vi.fn()];
      }
      if (savedQueriesMenuRenderState.stateCallIndex === 2) {
        return [{ top: 12, left: 24 }, vi.fn()];
      }

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

vi.mock('@/lib/i18n', () => {
  const labels: Record<string, string> = {
    'common.loading': 'Loading',
    'common.save': 'Save',
    'savedQueries.deleteAria': 'Delete saved filter',
    'savedQueries.empty': 'No saved filters yet.',
    'savedQueries.heading': 'Saved filters',
    'savedQueries.namePlaceholder': 'e.g. Urgent P1s',
    'savedQueries.saveCurrent': 'Save current filter',
    'savedQueries.trigger': 'Saved',
  };

  return {
    useI18n: () => ({
      format: (key: string, vars: Record<string, string>) => (
        key === 'savedQueries.deletedNamed' ? `Deleted "${vars.name}"` : key
      ),
      t: (key: string) => labels[key] ?? key,
    }),
  };
});

vi.mock('@/lib/hooks/useSavedQueries', () => ({
  useSavedQueries: () => ({
    isLoading: false,
    isSaving: false,
    remove: vi.fn(),
    save: vi.fn(),
    savedQueries: [
      {
        id: 'saved-1',
        view_type: 'AllTasks',
        name: 'Work focus',
        filter_json: '{"list":"work"}',
        created_at: '2026-05-08T17:00:00Z',
        updated_at: '2026-05-08T17:00:00Z',
      },
    ],
  }),
}));

vi.mock('@/lib/notifications/toast', () => ({
  toast: {
    errorWithDetail: vi.fn(),
    success: vi.fn(),
  },
}));

import { SavedQueriesMenu } from './SavedQueriesMenu';

describe('SavedQueriesMenu semantics', () => {
  beforeEach(() => {
    savedQueriesMenuRenderState.stateCallIndex = 0;
    vi.stubGlobal('document', { body: {} });
  });

  it('uses dialog/list/form controls instead of partial menu semantics', () => {
    const html = renderToStaticMarkup(
      <SavedQueriesMenu
        viewType="AllTasks"
        onApply={() => {}}
        onCapture={() => '{}'}
      />,
    );

    expect(html).toContain('role="dialog"');
    expect(html).not.toContain('role="menu"');
    expect(html).not.toContain('role="menuitem"');
    expect(html).not.toMatch(/<button[^>]+tabindex=/);
    expect(html).toContain('aria-label="Save current filter"');
    expect(html).toContain('>Work focus</button>');
    expect(html).toContain('aria-label="Delete saved filter: Work focus"');
  });
});
