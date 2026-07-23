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
    t: (key: string) => key,
  }),
}));

vi.mock('../ui/Tooltip', () => ({
  Tooltip: ({ children }: { children: ReactNode }) => children,
}));

import { TaskCardContent } from './TaskCardContent';
import type { TaskCardDisplayLabels } from './support';

const labels: TaskCardDisplayLabels = {
  aiNotes: 'AI notes',
  completed: 'Completed',
  complete: 'Complete',
  dependsOn: 'Depends on',
  dueToday: 'Due today',
  minuteSuffix: 'min',
  overdue: 'Overdue',
  priorityLabels: {
    1: 'High',
    2: 'Medium',
    3: 'Low',
  },
  recurrence: 'Recurrence',
  reopen: 'Reopen',
};

describe('TaskCardContent drag metadata', () => {
  it('renders drag keyboard metadata on the focusable task button', () => {
    const html = renderToStaticMarkup(
      <TaskCardContent
        task={{ id: 'task-1', title: 'Sharpen saw' } as never}
        isDone={false}
        completing={false}
        dueDateStr={null}
        overdue={false}
        tags={[]}
        checklistProgress={null}
        labels={labels}
        listInfo={null}
        onClick={vi.fn()}
        taskButtonAriaDescription="Move this task"
        taskButtonAriaRoleDescription="draggable"
        taskButtonAriaKeyShortcuts="Meta+ArrowUp Control+ArrowUp"
      />,
    );

    expect(html).toMatch(/^<button\b/);
    expect(html).toContain('aria-label="Sharpen saw"');
    expect(html).toContain('aria-description="Move this task"');
    expect(html).toContain('aria-roledescription="draggable"');
    expect(html).toContain('aria-keyshortcuts="Meta+ArrowUp Control+ArrowUp"');
  });

  it('can expose the task button as the single selection-mode checkbox control', () => {
    const html = renderToStaticMarkup(
      <TaskCardContent
        task={{ id: 'task-1', title: 'Sharpen saw' } as never}
        isDone={false}
        completing={false}
        dueDateStr={null}
        overdue={false}
        tags={[]}
        checklistProgress={null}
        labels={labels}
        listInfo={null}
        onClick={vi.fn()}
        taskButtonRole="checkbox"
        taskButtonAriaChecked
        taskButtonAriaLabel="Select task: Sharpen saw"
        taskButtonDisabled
      />,
    );

    expect(html).toMatch(/^<button\b/);
    expect(html).toContain('role="checkbox"');
    expect(html).toContain('aria-checked="true"');
    expect(html).toContain('aria-label="Select task: Sharpen saw"');
    expect(html).toContain('disabled=""');
  });
});
