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
      'contextMenu.promoteToActive': 'Promote to active',
      'popover.deferTomorrow': 'Defer until tomorrow',
      'task.defer.nextWeek': 'Defer until next week',
    })[key] ?? key,
  }),
}));

vi.mock('./useTaskCardQuickActionHandlers', () => ({
  useTaskCardQuickActionHandlers: () => ({
    actionPending: false,
    canPromote: true,
    handleDeferNextWeek: vi.fn(),
    handleDeferTomorrow: vi.fn(),
    handlePromote: vi.fn(),
    isActive: true,
  }),
}));

import { TaskCardQuickActions } from './TaskCardQuickActions';

describe('TaskCardQuickActions touch target sizing', () => {
  it('keeps touch-visible quick actions at app mobile target size without cramped gaps', () => {
    const html = renderToStaticMarkup(
      <TaskCardQuickActions task={{ id: 'task-1' } as never} />,
    );

    expect(html).toContain('gap-1');
    const buttonClassNames = [...html.matchAll(/<button\b[^>]*class="([^"]*)"/g)]
      .map((match) => match[1] ?? '');

    expect(buttonClassNames).toHaveLength(3);
    for (const className of buttonClassNames) {
      expect(className).toContain('min-w-6');
      expect(className).toContain('min-h-6');
      expect(className).toContain('[@media(hover:none)]:min-w-11');
      expect(className).toContain('[@media(hover:none)]:min-h-11');
    }
  });

  it('marks every quick action as ignored by the parent card long-press handler', () => {
    const html = renderToStaticMarkup(
      <TaskCardQuickActions task={{ id: 'task-1' } as never} />,
    );
    const ignoredButtons = [...html.matchAll(/<button\b[^>]*data-long-press-ignore=""/g)];

    expect(ignoredButtons).toHaveLength(3);
  });
});
