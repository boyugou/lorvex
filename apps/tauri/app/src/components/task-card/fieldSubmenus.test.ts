import { describe, expect, it } from 'vitest';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';
import type { TranslationKey } from '@/lib/i18n';
import { buildUpdateSubmenu } from './buildUpdateSubmenu';
import { buildRecurrenceMenuItem } from './fieldSubmenus';
import type { RunUpdate } from './types';

const t = (key: TranslationKey) => key;

function task(): Task {
  return {
    id: 'task-1',
    title: 'Recurring task',
    list_id: 'inbox',
    recurrence: null,
  } as Task;
}

describe('buildRecurrenceMenuItem', () => {
  it('sends structured recurrence objects from context-menu presets', () => {
    const calls: Array<{ updates: TaskUpdatePatch }> = [];
    const item = buildRecurrenceMenuItem(task(), t, (updates) => {
      calls.push({ updates });
    });

    item.submenu?.find((candidate) => candidate.key === 'recur-weekly')?.onSelect?.();

    expect(calls).toEqual([{
      updates: {
        recurrence: { FREQ: 'WEEKLY', INTERVAL: 1 },
      },
    }]);
  });

  it('types dynamic update submenu fields against the task update patch contract', () => {
    const runUpdate: RunUpdate = () => {};

    buildUpdateSubmenu({
      presets: [{ key: 'priority-1', labelKey: 'task.priority', value: 1 }],
      fieldName: 'priority',
      source: 'contextMenu.priority',
      errorMessage: 'Failed to update priority',
      clearItem: {
        key: 'priority-clear',
        labelKey: 'task.noPriority',
        errorMessage: 'Failed to clear priority',
      },
    }, t, runUpdate);

    buildUpdateSubmenu({
      presets: [{ key: 'bad', labelKey: 'task.priority', value: 1 }],
      // @ts-expect-error dynamic submenu builders must reject unsupported update fields.
      fieldName: 'unknown_field',
      source: 'contextMenu.priority',
      errorMessage: 'Failed to update priority',
    }, t, runUpdate);

    buildUpdateSubmenu({
      presets: [
        // @ts-expect-error priority presets must use the typed priority value, not a label string.
        { key: 'priority-high', labelKey: 'task.priority', value: 'high' },
      ],
      fieldName: 'priority',
      source: 'contextMenu.priority',
      errorMessage: 'Failed to update priority',
    }, t, runUpdate);
  });
});
