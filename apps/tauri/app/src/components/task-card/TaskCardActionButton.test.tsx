import type { ReactNode } from 'react';
import { describe, expect, it, vi } from 'vitest';

type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const { renderToStaticMarkup } = req('react-dom/server') as {
  renderToStaticMarkup: (node: ReactNode) => string;
};

vi.mock('../ui/Tooltip', () => ({
  Tooltip: ({ children }: { children: ReactNode }) => children,
}));

import { TaskCardActionButton } from './TaskCardActionButton';
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

function renderButton(props: Partial<Parameters<typeof TaskCardActionButton>[0]> = {}) {
  return renderToStaticMarkup(
    <TaskCardActionButton
      isDone={false}
      canQuickReopen={false}
      disableComplete={false}
      completing={false}
      reopening={false}
      labels={labels}
      onComplete={vi.fn()}
      onReopen={vi.fn()}
      {...props}
    />,
  );
}

describe('TaskCardActionButton long-press isolation', () => {
  it('marks circle, ranked, and reopen controls as ignored by the parent long-press handler', () => {
    expect(renderButton()).toContain('data-long-press-ignore=""');
    expect(renderButton({ rank: 1 })).toContain('data-long-press-ignore=""');
    expect(renderButton({ isDone: true, canQuickReopen: true })).toContain(
      'data-long-press-ignore=""',
    );
  });
});
