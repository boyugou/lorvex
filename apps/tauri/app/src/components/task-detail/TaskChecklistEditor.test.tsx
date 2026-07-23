import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import type { TaskChecklistItem } from '@/lib/ipc/tasks/models';
import TaskChecklistEditor from './TaskChecklistEditor';

vi.mock('@/lib/i18n', () => {
  const labels: Record<string, string> = {
    'common.add': 'Add',
    'common.remove': 'Remove',
    'task.checklist': 'Checklist',
    'task.checklistEmpty': 'No checklist items yet',
    'task.checklistItemLabel': 'Checklist item text',
    'task.checklistMoveDown': 'Move down',
    'task.checklistMoveUp': 'Move up',
    'task.checklistPlaceholder': 'Add checklist item',
  };

  return {
    useI18n: () => ({
      locale: 'en',
      t: (key: string) => labels[key] ?? key,
    }),
  };
});

vi.mock('@/lib/ipc/tasks/mutations/checklist', () => ({
  addTaskChecklistItem: vi.fn(),
  removeTaskChecklistItem: vi.fn(),
  reorderTaskChecklistItems: vi.fn(),
  setTaskChecklistItemCompleted: vi.fn(),
  updateTaskChecklistItemText: vi.fn(),
}));

vi.mock('@/lib/notifications/toast', () => ({
  toast: {
    errorWithDetail: vi.fn(),
  },
}));

function checklistItem(overrides: Partial<TaskChecklistItem> = {}): TaskChecklistItem {
  return {
    id: 'item-1',
    task_id: 'task-1',
    position: 0,
    text: 'Buy milk',
    completed_at: null,
    version: '1',
    created_at: '2026-05-08T17:00:00Z',
    updated_at: '2026-05-08T17:00:00Z',
    ...overrides,
  };
}

describe('TaskChecklistEditor accessibility', () => {
  it('labels add, toggle, move, and remove controls with checklist item context', () => {
    const html = renderToStaticMarkup(
      <TaskChecklistEditor
        taskId="task-1"
        items={[
          checklistItem(),
          checklistItem({ id: 'item-2', position: 1, text: 'Book flights' }),
        ]}
        refetchTask={async () => {}}
      />,
    );

    expect(html).toContain('aria-label="Add checklist item"');
    expect(html).toContain('aria-label="Checklist: Buy milk"');
    expect(html).toContain('aria-label="Move up: Buy milk"');
    expect(html).toContain('aria-label="Move down: Buy milk"');
    expect(html).toContain('aria-label="Remove: Buy milk"');
    expect(html.match(/min-h-6/g)?.length ?? 0).toBeGreaterThanOrEqual(7);
    expect(html.match(/min-w-6/g)?.length ?? 0).toBeGreaterThanOrEqual(7);
  });
});
