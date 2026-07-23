import { renderToStaticMarkup } from 'react-dom/server';
import type { ReactNode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { ListViewContentProps } from './ListViewContext';

const listViewState = vi.hoisted(() => ({
  current: null as ListViewContentProps | null,
}));

vi.mock('@/lib/i18n', () => ({
  useI18n: () => ({
    formatNumber: (value: number) => String(value),
    t: (key: string) => ({
      'allTasks.select': 'Select',
      'common.copying': 'Copying',
      'common.done': 'Done',
      'common.saving': 'Saving',
      'list.copyPlan': 'Copy plan',
      'list.delete': 'Delete list',
      'list.planCopied': 'Plan copied',
      'list.rename': 'Rename list',
    })[key] ?? key,
  }),
}));

vi.mock('@/lib/platform/useCopyToClipboard', () => ({
  useCopyToClipboard: () => ({
    copy: vi.fn(),
    copying: false,
  }),
}));

vi.mock('../ui/Tooltip', () => ({
  Tooltip: ({ children }: { children: ReactNode }) => <>{children}</>,
}));

vi.mock('./ListViewContext', () => ({
  useListView: () => {
    if (!listViewState.current) throw new Error('missing test ListViewHeader context');
    return listViewState.current;
  },
}));

import { ListViewHeader } from './ListViewHeader';

function createListViewContext(overrides: Partial<ListViewContentProps> = {}): ListViewContentProps {
  return {
    adding: false,
    allTags: [],
    bulk: { bulkAction: null } as never,
    completedTasks: [],
    data: {
      list: {
        color: '#3b82f6',
        description: 'Launch checklist',
        icon: '✓',
        id: 'list-1',
        name: 'Project Alpha',
      },
      tasks: [],
      total_matching: 1,
    } as never,
    deleting: false,
    draft: '',
    filterPriority: null,
    focusedTaskId: null,
    inputRef: { current: null },
    isFilterActive: false,
    onAdd: vi.fn(),
    onCancelRename: vi.fn(),
    onClearSelection: vi.fn(),
    onClearTagFilter: vi.fn(),
    onClickWithModifiers: vi.fn(),
    onDeleteList: vi.fn(),
    onDraftChange: vi.fn(),
    onFilterPriorityChange: vi.fn(),
    onRename: vi.fn(),
    onSearchChange: vi.fn(),
    onSelectAll: vi.fn(),
    onSetSelectionMode: vi.fn(),
    onSortKeyChange: vi.fn(),
    onStartRename: vi.fn(),
    onToggleSelected: vi.fn(),
    onToggleSortDirection: vi.fn(),
    onToggleTag: vi.fn(),
    openTasks: [{ id: 'task-1' } as never],
    renameSaving: false,
    renaming: false,
    scrollContainerRef: { current: null },
    search: '',
    selectedIds: new Set(),
    selectedTags: new Set(),
    selectionMode: false,
    sortDirection: 'asc',
    sortKey: 'priority',
    totalOpenCount: 1,
    usesMobileLayout: false,
    ...overrides,
  };
}

describe('ListViewHeader heading semantics', () => {
  beforeEach(() => {
    listViewState.current = createListViewContext();
  });

  it('keeps the list name as a heading and exposes rename as a separate named button', () => {
    const html = renderToStaticMarkup(<ListViewHeader />);
    const headingMatch = html.match(/<h2\b(?![^>]*role="button")[^>]*>[\s\S]*?<button\b[^>]*aria-labelledby="([^"]+)"[^>]*>[\s\S]*?Project Alpha[\s\S]*?<\/button>[\s\S]*?<\/h2>/);

    expect(headingMatch).not.toBeNull();
    const labelledBy = headingMatch?.[1] ?? '';
    const [actionLabelId, titleId] = labelledBy.split(' ');

    expect(html).toContain(`id="${actionLabelId}"`);
    expect(html).toContain('Rename list');
    expect(html).toContain(`id="${titleId}"`);
    expect(html).toContain('Project Alpha');
    expect(html).not.toContain('<h2 role="button"');
    expect(html).not.toContain('tabindex="0"');
  });
});
