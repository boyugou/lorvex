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
    formatNumber: (value: number) => String(value),
    t: (key: string) => key,
  }),
}));

vi.mock('@/lib/useScrollRestore', () => ({
  useScrollRestore: () => ({
    onScroll: vi.fn(),
    ref: { current: null },
  }),
}));

vi.mock('../task-card/TaskCard', () => ({
  default: ({ task }: { task: { id: string } }) => (
    <div className="cv-task-card min-w-0 flex-1" data-task-id={task.id}>
      <span>Task card</span>
      <span className="reveal-on-hover [@media(hover:none)]:min-w-11">Quick actions</span>
    </div>
  ),
}));

vi.mock('../task-card/SwipeableTaskCard', () => ({
  SwipeableTaskCard: ({ children }: { children: ReactNode }) => <>{children}</>,
}));

vi.mock('../context-menu/ContextMenu', () => ({
  ContextMenu: () => null,
}));

import KanbanMobileView from './KanbanMobileView';
import type { KanbanController } from './useKanbanController';

function createController(): KanbanController {
  const task = {
    id: 'task-1',
    estimated_minutes: 15,
    status: 'open',
  };
  return {
    allFlatTasks: [task],
    columns: {
      open: [task],
      someday: [],
      completed: [],
    },
    filteredTasks: [task],
    handleDrop: vi.fn(),
    isError: false,
    isFilterActive: false,
    isLoading: false,
    keyboard: {
      isFocused: () => false,
    },
    moveToColumnPending: false,
    refetch: vi.fn(),
    t: (key: string) => key,
    totalTaskCount: 1,
    visibleColumnKeys: ['open', 'someday', 'completed'],
  } as unknown as KanbanController;
}

describe('KanbanMobileView task row layout', () => {
  it('renders the mobile move control as an adjacent flex item instead of overlaying task quick actions', () => {
    const html = renderToStaticMarkup(<KanbanMobileView controller={createController()} />);

    expect(html).toContain('data-kanban-mobile-task-row="true"');
    expect(html).toMatch(/data-kanban-mobile-task-row="true"[^>]*class="[^"]*\bflex\b[^"]*\bgap-2\b/);

    const moveButtonMatch = html.match(/<button\b[^>]*aria-label="kanban\.mobile\.moveTo"[^>]*class="([^"]*)"/);
    expect(moveButtonMatch?.[1]).toBeDefined();
    expect(moveButtonMatch?.[1]).not.toContain('absolute');
    expect(moveButtonMatch?.[1]).not.toContain('z-[var(--z-sticky)]');
    expect(moveButtonMatch?.[1]).toContain('shrink-0');
    expect(moveButtonMatch?.[1]).toContain('min-h-11');
    expect(moveButtonMatch?.[1]).toContain('min-w-11');
  });
});
