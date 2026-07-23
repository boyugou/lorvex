import { useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import type { Task } from '@/lib/ipc/tasks/models';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';
import { invalidateListQueries, invalidateTaskMutationQueries } from '@/lib/query/queryKeys';
import { toast } from '@/lib/notifications/toast';

interface CommitTaskPickerUpdateArgs {
  patch: TaskUpdatePatch;
  successMessage: string;
  errorKey: string;
  errorMessage: string;
  extraListIds?: Array<string | null | undefined>;
}

export function useTaskPickerMutation(task: Task | undefined, onClose: () => void) {
  const { t } = useI18n();
  const queryClient = useQueryClient();

  const commitTaskPickerUpdate = useCallback(({
    patch,
    successMessage,
    errorKey,
    errorMessage,
    extraListIds = [],
  }: CommitTaskPickerUpdateArgs) => {
    if (!task) {
      onClose();
      return;
    }

    const listIds = new Set(
      [task.list_id, ...extraListIds].filter((value): value is string => typeof value === 'string' && value.length > 0),
    );

    void updateTask(task.id, patch)
      .then(() => {
        invalidateTaskMutationQueries(queryClient, { listId: task.list_id });
        for (const listId of listIds) {
          if (listId === task.list_id) {
            continue;
          }
          invalidateListQueries(queryClient, listId);
        }
        toast.success(successMessage);
      })
      .catch((error) => {
        reportClientError(errorKey, errorMessage, error);
        toast.errorWithDetail(error, t('common.error'));
      });

    onClose();
  }, [onClose, queryClient, t, task]);

  return {
    commitTaskPickerUpdate,
  };
}
