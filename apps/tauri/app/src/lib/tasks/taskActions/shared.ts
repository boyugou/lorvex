import type { MutableRefObject } from 'react';
import type { QueryClient } from '@tanstack/react-query';

import { DEFER_REASON_NOT_TODAY } from '@lorvex/shared/types';

import { isTaskActive } from '../../format';
import { reportClientError } from '../../errors/errorLogging';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TaskUpdatePatch, TaskWithUndo } from '@/lib/ipc/tasks/mutations/types';
import type { useI18n } from '../../i18n';
import {
  applyOptimisticTaskPatch,
  rollbackOptimisticTaskPatch,
  type TaskPatch,
} from '../../query/optimisticEntity';
import { invalidateTaskMutationQueries } from '../../query/queryKeys';
import { toast } from '../../notifications/toast';
import { showUndoOnlyToast } from '../lifecycleUndoRedo';

export const WEEKLY_RECURRENCE_PATCH = { FREQ: 'WEEKLY', INTERVAL: 1 } satisfies NonNullable<TaskUpdatePatch['recurrence']>;
export const WEEKLY_RECURRENCE = JSON.stringify(WEEKLY_RECURRENCE_PATCH);
export { DEFER_REASON_NOT_TODAY };

interface TaskActionDayContext {
  timezone: string;
  todayYmd: string;
  tomorrowYmd: string;
}

export interface TaskListActionDeps {
  tasksRef: MutableRefObject<Task[]>;
  dayContextRef: MutableRefObject<TaskActionDayContext>;
  qc: QueryClient;
  t: ReturnType<typeof useI18n>['t'];
  format: ReturnType<typeof useI18n>['format'];
}

export function getActiveTask(tasks: Task[], taskId: string): Task | null {
  const task = tasks.find((tk) => tk.id === taskId);
  if (!task) return null;
  return isTaskActive(task.status) ? task : null;
}

export function undoableAction(
  opts: {
    action: () => Promise<TaskWithUndo>;
    successMsg: string;
    errorKey: string;
    errorMsg: string;
    listId: string | null;
    qc: QueryClient;
    t: ReturnType<typeof useI18n>['t'];
    optimistic?: { taskId: string; patch: TaskPatch };
  },
): void {
  void (async () => {
    const snapshot = opts.optimistic
      ? await applyOptimisticTaskPatch(opts.qc, opts.optimistic.taskId, opts.optimistic.patch)
      : null;
    try {
      const result = await opts.action();
      invalidateTaskMutationQueries(opts.qc, { listId: opts.listId });
      showUndoOnlyToast(opts.successMsg, result.undo_token, {
        invalidate: () => invalidateTaskMutationQueries(opts.qc, { listId: opts.listId }),
        t: opts.t,
        errorKeyPrefix: opts.errorKey,
      });
    } catch (error) {
      if (snapshot) rollbackOptimisticTaskPatch(opts.qc, snapshot);
      reportClientError(opts.errorKey, opts.errorMsg, error);
      toast.errorWithDetail(error, opts.t('common.error'));
    }
  })();
}
