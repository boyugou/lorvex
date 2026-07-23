import { useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { addTaskDependency, removeTaskDependency } from '@/lib/ipc/tasks/mutations/dependencies';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { invalidateTaskDependencyQueries } from '@/lib/query/queryKeys';
import { toast } from '@/lib/notifications/toast';

interface UseTaskDetailRelationActionsArgs {
  taskId: string | null;
}

export function useTaskDetailRelationActions({
  taskId,
}: UseTaskDetailRelationActionsArgs) {
  const queryClient = useQueryClient();
  const { t } = useI18n();

  const invalidateDepsFor = useCallback((otherId: string | null) => {
    if (!taskId) return;
    invalidateTaskDependencyQueries(queryClient, { taskId, relatedTaskId: otherId });
  }, [queryClient, taskId]);

  const handleRemoveDependsOn = useCallback(async (removeId: string) => {
    if (!taskId) return;
    try {
      await removeTaskDependency(taskId, removeId);
      invalidateDepsFor(removeId);
    } catch (error) {
      reportClientError('task-detail.relations', 'Failed to remove dependency', error);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [invalidateDepsFor, t, taskId]);

  const handleAddDependsOn = useCallback(async (addId: string) => {
    if (!taskId || addId === taskId) return;
    try {
      await addTaskDependency(taskId, addId);
      invalidateDepsFor(addId);
    } catch (error) {
      reportClientError('task-detail.relations', 'Failed to add dependency', error);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [invalidateDepsFor, t, taskId]);

  const handleAddBlocks = useCallback(async (targetId: string) => {
    if (!taskId || targetId === taskId) return;
    try {
      await addTaskDependency(targetId, taskId);
      invalidateDepsFor(targetId);
    } catch (error) {
      reportClientError('task-detail.relations', 'Failed to add dependency', error);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [invalidateDepsFor, t, taskId]);

  const handleRemoveBlocks = useCallback(async (targetId: string) => {
    if (!taskId) return;
    try {
      await removeTaskDependency(targetId, taskId);
      invalidateDepsFor(targetId);
    } catch (error) {
      reportClientError('task-detail.relations', 'Failed to remove dependency', error);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [invalidateDepsFor, t, taskId]);

  return {
    handleAddBlocks,
    handleAddDependsOn,
    handleRemoveBlocks,
    handleRemoveDependsOn,
  };
}
