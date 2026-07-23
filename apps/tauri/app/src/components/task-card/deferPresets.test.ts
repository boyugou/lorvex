import { describe, expect, it } from 'vitest';

import type { DayContext } from '@/lib/dayContext';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';
import type { TranslationKey } from '@/lib/i18n';
import { buildDueDateMenuItem } from './deferPresets';

const dayContext: DayContext = {
  timezone: 'America/Los_Angeles',
  todayYmd: '2026-05-08',
  tomorrowYmd: '2026-05-09',
};

const t = (key: TranslationKey) => key;

function taskWithDueTime(): Task {
  return {
    id: 'task-1',
    title: 'Timed task',
    list_id: 'inbox',
    due_date: '2026-05-10',
    due_time: '09:30',
  } as Task;
}

describe('buildDueDateMenuItem', () => {
  it('clears due_time when clearing a timed due date from the context menu', () => {
    const calls: Array<{
      updates: TaskUpdatePatch;
      source: string;
      errorMessage: string;
      successToast: string | undefined;
    }> = [];
    const item = buildDueDateMenuItem(taskWithDueTime(), dayContext, t, (
      updates,
      source,
      errorMessage,
      successToast,
    ) => {
      calls.push({ updates, source, errorMessage, successToast });
    });

    item.submenu?.find((candidate) => candidate.key === 'due-clear')?.onSelect?.();

    expect(calls).toEqual([{
      updates: { due_date: null, due_time: null },
      source: 'contextMenu.dueDate',
      errorMessage: 'Failed to clear due date',
      successToast: undefined,
    }]);
  });
});
