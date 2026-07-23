import { useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';
import {
  applyOptimisticTaskPatch,
  rollbackOptimisticTaskPatch,
  type TaskPatch,
} from '@/lib/query/optimisticEntity';
import { toast } from '@/lib/notifications/toast';
import { reportTaskDetailActionError } from '@/components/task-detail/support';
import type { UseTaskDetailMutationDeps } from './types';

/**
 * Project a typed `updateTask` IPC patch onto the cached `Task` shape
 * for optimistic updates. `undefined` means "field absent" and is
 * dropped; `null` remains meaningful for clearable fields. The IPC
 * recurrence patch is structured, while the cached task stores the
 * backend-normalized JSON string, so stringify only that field.
 */
function projectTaskPatch(patch: TaskUpdatePatch): TaskPatch {
  const projected: TaskPatch = {};
  for (const key of Object.keys(patch) as Array<keyof TaskUpdatePatch>) {
    const value = patch[key];
    if (value === undefined) {
      continue;
    }
    if (key === 'recurrence') {
      projected.recurrence = value === null ? null : JSON.stringify(value);
      continue;
    }
    (projected as Record<keyof TaskPatch, unknown>)[key as keyof TaskPatch] = value;
  }
  return projected;
}

export function useTaskDetailMetadataMutations({
  invalidateAll,
  persistDraftsRef,
  task,
  t,
}: UseTaskDetailMutationDeps) {
  const queryClient = useQueryClient();
  const saveMetaPatch = useCallback(async (patch: TaskUpdatePatch): Promise<boolean> => {
    if (!task) return false;
    const ok = await persistDraftsRef.current();
    if (!ok) return false;

    // Optimistically reflect the patch in every cached `Task` view
    // of this id (single-task panel, today/upcoming/calendar lists,
    // …). Tag add/remove from the inline editor goes through here;
    // keeping the cache forward means the chip animation runs once
    // in the right direction instead of repainting the old chip set
    // for ~150ms while the IPC settles.
    const optimisticPatch = projectTaskPatch(patch);
    const taskId = task.id;
    const snapshot = Object.keys(optimisticPatch).length > 0
      ? await applyOptimisticTaskPatch(queryClient, taskId, optimisticPatch)
      : null;

    try {
      await updateTask(taskId, patch);
      const candidateListId = patch.list_id;
      const nextListId = typeof candidateListId === 'string' ? candidateListId : null;
      invalidateAll({
        extraListIds: nextListId !== null && nextListId !== task.list_id ? [nextListId] : [],
      });
      return true;
    } catch (taskError) {
      if (snapshot) rollbackOptimisticTaskPatch(queryClient, snapshot);
      reportTaskDetailActionError('save-metadata', taskError, taskId);
      toast.errorWithDetail(taskError, t('common.error'));
      return false;
    }
  }, [invalidateAll, persistDraftsRef, queryClient, t, task]);

  return { saveMetaPatch };
}
