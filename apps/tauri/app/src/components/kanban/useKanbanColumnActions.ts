import { useMutation, useQueryClient } from '@tanstack/react-query';
import { completeTask, reopenTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { reportClientError } from '@/lib/errors/errorLogging';
import type { TranslationKey } from '@/lib/i18n';
import {
  applyOptimisticTaskPatch,
  rollbackOptimisticTaskPatch,
  type OptimisticTaskSnapshot,
} from '@/lib/query/optimisticEntity';
import { invalidateTaskStatusChangeQueries } from '@/lib/query/queryKeys';
import {
  showUndoOnlyToast,
  showUndoToastWithRedo,
} from '@/lib/tasks/lifecycleUndoRedo';
import { toast } from '@/lib/notifications/toast';
import { COLUMN_TO_STATUS, type ColumnKey } from './columns';

interface UseKanbanColumnActionsArgs {
  t: (key: TranslationKey) => string;
}

// `completeTask` returns TaskWithUndo. The old Kanban
// drag handler threw the undo_token away — a user who accidentally
// dragged a task into the Completed column had no recovery short of
// finding it in a filtered view. Thread the token through a
// discriminated MoveResult so onSuccess can wire the toast action.
//
// extend the undo affordance to the `someday` branch — moving
// a task to the someday column rewrites status via `updateTask`,
// which already produces an undo token. The `open` branch routes
// through `reopenTask` whose semantics include side effects
// (reminder un-cancellation, successor handling) that the generic
// task-update undo path doesn't reverse cleanly, so it remains a
// plain success toast. A backend-side reopen-undo is filed as
// follow-up rather than reused via the update token here.
type MoveResult =
  | { kind: 'completed'; undoToken: string }
  | { kind: 'open' }
  | { kind: 'someday'; undoToken: string };

interface OptimisticContext {
  /**
   * delegate the optimistic patch + rollback to the shared
   * `applyOptimisticTaskPatch` helper. The helper sweeps every
   * task-bearing query key (not just the two all-tasks variants the
   * Kanban view subscribes to) and snapshots the prior `status` value
   * per-task per-key, so rolling back one in-flight drag never
   * disturbs another concurrent optimistic mutation.
   */
  snapshot: OptimisticTaskSnapshot;
}

export function useKanbanColumnActions({
  t,
}: UseKanbanColumnActionsArgs) {
  const queryClient = useQueryClient();

  const moveToColumn = useMutation<
    MoveResult,
    Error,
    { taskId: string; target: ColumnKey },
    OptimisticContext
  >({
    mutationFn: async ({
      taskId,
      target,
    }: {
      taskId: string;
      target: ColumnKey;
    }): Promise<MoveResult> => {
      switch (target) {
        case 'completed': {
          const result = await completeTask(taskId);
          return { kind: 'completed', undoToken: result.undo_token };
        }
        case 'open':
          await reopenTask(taskId);
          return { kind: 'open' };
        case 'someday': {
          const updated = await updateTask(taskId, { status: 'someday' });
          return { kind: 'someday', undoToken: updated.undo_token };
        }
      }
    },
    onMutate: async ({ taskId, target }): Promise<OptimisticContext> => {
      // patch the cached task's status synchronously so
      // the dragged card lands in its new column on the same paint as
      // the drop. Without this, the card snaps back to its source column
      // for the duration of the IPC round-trip and then jumps again when
      // the invalidate-driven refetch lands. The shared helper covers
      // the all-tasks (showCompleted: false / true) keys and any other
      // task-bearing query that happens to hold the dragged task.
      const targetStatus = COLUMN_TO_STATUS[target];
      const snapshot = await applyOptimisticTaskPatch(queryClient, taskId, {
        status: targetStatus,
      });
      return { snapshot };
    },
    onSuccess: (result) => {
      invalidateTaskStatusChangeQueries(queryClient);
      if (result.kind === 'completed') {
        showUndoToastWithRedo(t('kanban.moved'), result.undoToken, {
          invalidate: () => invalidateTaskStatusChangeQueries(queryClient),
          t,
          errorKeyPrefix: 'kanban.complete',
        });
      } else if (result.kind === 'someday') {
        showUndoOnlyToast(t('kanban.moved'), result.undoToken, {
          invalidate: () => invalidateTaskStatusChangeQueries(queryClient),
          t,
          errorKeyPrefix: 'kanban.someday',
        });
      } else {
        toast.success(t('kanban.moved'));
      }
    },
    onError: (error, _variables, context) => {
      // restore the source task's prior `status` field via the
      // shared snapshot. Per-entry, per-field rollback leaves any
      // concurrent in-flight optimistic mutations (other kanban drags,
      // lifecycle actions, eisenhower priority swaps) untouched.
      if (context) rollbackOptimisticTaskPatch(queryClient, context.snapshot);
      reportClientError('kanban', 'Failed to move task between columns', error);
      toast.errorWithDetail(error, t('common.error'));
    },
  });

  return {
    handleMoveToColumn: (taskId: string, target: ColumnKey) => {
      moveToColumn.mutate({ taskId, target });
    },
    isMovingToColumn: moveToColumn.isPending,
  };
}
