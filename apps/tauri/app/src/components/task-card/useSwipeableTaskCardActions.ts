import { useCallback, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { useDayContext } from '@/lib/DayContextProvider';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import type { Task } from '@/lib/ipc/tasks/models';
import { deferTaskUntil } from '@/lib/ipc/tasks/mutations/deferral';
import { completeTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { invalidateTaskMutationQueries, invalidateTaskQueries } from '@/lib/query/queryKeys';
import { runTaskDeferralWithUndo } from '@/lib/tasks/deferralUndo';
import { showUndoToastWithRedo } from '@/lib/tasks/lifecycleUndoRedo';
import { toast } from '@/lib/notifications/toast';
import { DEFER_REASON_NOT_TODAY } from '@lorvex/shared/types';
import { TASK_COMPLETE_ANIMATION_DELAY_MS } from './support';
import {
  clearTaskCardCompletionRefresh,
  createBrowserTaskCardCompletionRefreshTimerHost,
  scheduleTaskCardCompletionRefresh,
} from './taskCardCompletionRefresh.runtime';

export function useSwipeableTaskCardActions(task: Task, resetCardPosition: () => void) {
  const { t, format } = useI18n();
  const queryClient = useQueryClient();
  const dayContext = useDayContext();
  const completeTimerRef = useRef<unknown | null>(null);

  const invalidateCaches = useCallback(() => {
    invalidateTaskMutationQueries(queryClient, { listId: task.list_id });
    invalidateTaskQueries(queryClient, task.id);
  }, [queryClient, task.id, task.list_id]);

  const handleSwipeComplete = useCallback(async () => {
    try {
      const result = await completeTask(task.id);
      showUndoToastWithRedo(format('task.status.completedNamed', { title: task.title }), result.undo_token, {
        invalidate: invalidateCaches,
        t,
        errorKeyPrefix: 'swipe.complete',
      });
      completeTimerRef.current = scheduleTaskCardCompletionRefresh({
        delayMs: TASK_COMPLETE_ANIMATION_DELAY_MS,
        refresh: invalidateCaches,
        timerHost: createBrowserTaskCardCompletionRefreshTimerHost(),
      });
    } catch (error) {
      reportClientError('swipe.complete', 'Failed to complete task via swipe', error, task.id);
      toast.errorWithDetail(error, t('common.error'));
      resetCardPosition();
    }
  }, [format, invalidateCaches, resetCardPosition, t, task.id, task.title]);

  const handleSwipeDefer = useCallback(async () => {
    await runTaskDeferralWithUndo({
      task,
      runDefer: () => deferTaskUntil(task.id, dayContext.tomorrowYmd, DEFER_REASON_NOT_TODAY),
      invalidate: invalidateCaches,
      successMessage: t('popover.deferTomorrow'),
      undoLabel: t('common.undo'),
      forwardErrorSource: 'swipe.defer',
      forwardErrorMessage: 'Failed to defer task via swipe',
      forwardErrorDetails: task.id,
      forwardErrorToastMessage: t('common.error'),
      onForwardError: resetCardPosition,
      undoErrorSource: 'swipe.undoDefer',
      undoErrorMessage: 'Failed to undo swipe defer',
      undoErrorDetails: task.id,
      undoErrorLevel: 'warn',
      undoErrorToastMessage: t('common.error'),
    });
  }, [dayContext.tomorrowYmd, invalidateCaches, resetCardPosition, t, task]);

  const clearSwipeCompletionTimer = useCallback(() => {
    if (completeTimerRef.current == null) return;
    clearTaskCardCompletionRefresh(
      createBrowserTaskCardCompletionRefreshTimerHost(),
      completeTimerRef.current,
    );
    completeTimerRef.current = null;
  }, []);

  return {
    clearSwipeCompletionTimer,
    handleSwipeComplete,
    handleSwipeDefer,
  };
}
