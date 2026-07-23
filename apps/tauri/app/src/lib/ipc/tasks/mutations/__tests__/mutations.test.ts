import { beforeEach, describe, expect, it, vi } from 'vitest';

import { invoke, invokeIpc } from '@/lib/ipc/core';
import { getArchivedTasks } from '@/lib/ipc/tasks/mutations/lifecycle';
import { quickCapture, updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';

vi.mock('../../../core', () => ({
  invoke: vi.fn(),
  invokeIpc: vi.fn(),
}));

const invokeMock = vi.mocked(invoke);
const invokeIpcMock = vi.mocked(invokeIpc);

describe('quickCapture IPC wrapper', () => {
  beforeEach(() => {
    invokeMock.mockReset();
    invokeIpcMock.mockReset();
    invokeMock.mockResolvedValue({ tasks: [], total_matching: 0 });
    invokeIpcMock.mockResolvedValue({ id: 'task-1' });
  });

  it('uses the single options-object call shape and forwards AbortSignal to invokeIpc', async () => {
    const controller = new AbortController();

    await quickCapture({
      body: 'Details',
      dueDate: '2026-05-02',
      estimatedMinutes: 45,
      listId: 'list-1',
      priority: 2,
      signal: controller.signal,
      status: 'someday',
      tags: ['alpha', 'beta'],
      title: 'Write report',
    });

    expect(invokeIpcMock).toHaveBeenCalledWith(
      'quick_capture',
      {
        request: {
          body: 'Details',
          due_date: '2026-05-02',
          estimated_minutes: 45,
          list_id: 'list-1',
          priority: 2,
          status: 'someday',
          tags: ['alpha', 'beta'],
          title: 'Write report',
        },
      },
      controller.signal,
    );
  });

  it('normalizes omitted optional fields to null for the backend command', async () => {
    await quickCapture({ title: 'Inbox task' });

    expect(invokeIpcMock).toHaveBeenCalledWith(
      'quick_capture',
      {
        request: {
          body: null,
          due_date: null,
          estimated_minutes: null,
          list_id: null,
          priority: null,
          status: null,
          tags: null,
          title: 'Inbox task',
        },
      },
      undefined,
    );
  });

  it('drops undefined task update fields while preserving null clears', async () => {
    await updateTask('task-1', {
      due_date: null,
      due_time: undefined,
      priority: 2,
    });

    expect(invokeIpcMock).toHaveBeenCalledWith(
      'update_task',
      {
        id: 'task-1',
        updates: {
          due_date: null,
          priority: 2,
        },
      },
      undefined,
    );
    const [, payload] = invokeIpcMock.mock.calls[0] as [
      string,
      { updates: Record<string, unknown> },
      AbortSignal | undefined,
    ];
    expect(Object.hasOwn(payload.updates, 'due_time')).toBe(false);
    expect(Object.hasOwn(payload.updates, 'due_date')).toBe(true);
  });

  it('exposes a narrow compile-time task update patch contract', () => {
    const acceptUpdatePatch = (_patch: Parameters<typeof updateTask>[1]) => {};

    acceptUpdatePatch({
      depends_on: ['task-parent'],
      due_date: null,
      due_time: '09:30',
      estimated_minutes: 45,
      priority: 1,
      recurrence: { FREQ: 'WEEKLY', INTERVAL: 1 },
      status: 'open',
      tags: ['work'],
    });

    // @ts-expect-error unsupported task update fields must fail before IPC.
    acceptUpdatePatch({ unknown_field: true });

    // @ts-expect-error priority accepts numeric priority values or null, not labels.
    acceptUpdatePatch({ priority: 'high' });
  });

  it('keeps archived task reads off the mutation IPC broadcast path', async () => {
    const controller = new AbortController();

    await getArchivedTasks({ limit: 20, offset: 40 }, controller.signal);

    expect(invokeMock).toHaveBeenCalledWith(
      'get_archived_tasks',
      { limit: 20, offset: 40 },
      controller.signal,
    );
    expect(invokeIpcMock).not.toHaveBeenCalledWith(
      'get_archived_tasks',
      expect.anything(),
      expect.anything(),
      expect.anything(),
    );
  });
});
