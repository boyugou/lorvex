import { useCallback, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import type { Task } from '@/lib/ipc/tasks/models';
import { completeTask, reopenTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { quickCapture, updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import type { TranslationKey } from '@/lib/i18n';
import { invalidateTodaySurfaceQueries } from '@/lib/query/queryKeys';
import { showUndoToastWithRedo } from '@/lib/tasks/lifecycleUndoRedo';
import { buildDueTimePatch } from '@/lib/tasks/dueAtPatch.logic';
import { toast } from '@/lib/notifications/toast';
import { reportCalendarTaskActionError } from '../viewSupport';

interface UseDayPanelTaskActionsArgs {
  date: string;
  onInvalidate: () => void;
  t: (key: TranslationKey) => string;
}

export function useDayPanelTaskActions({
  date,
  onInvalidate,
  t,
}: UseDayPanelTaskActionsArgs) {
  const queryClient = useQueryClient();
  const [addingTask, setAddingTask] = useState(false);

  const invalidateDayPanel = useCallback(() => {
    invalidateTodaySurfaceQueries(queryClient);
    onInvalidate();
  }, [onInvalidate, queryClient]);

  const handleComplete = useCallback(async (task: Task) => {
    try {
      const result = await completeTask(task.id);
      invalidateDayPanel();
      showUndoToastWithRedo(t('task.status.completed'), result.undo_token, {
        invalidate: invalidateDayPanel,
        t,
        errorKeyPrefix: 'calendar.day.complete',
      });
    } catch (error) {
      reportCalendarTaskActionError('day.complete', error, task.id);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [invalidateDayPanel, t]);

  const handleReopen = useCallback(async (task: Task) => {
    try {
      await reopenTask(task.id);
      invalidateDayPanel();
      toast.info(t('task.undone'));
    } catch (error) {
      reportCalendarTaskActionError('day.reopen', error, task.id);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [invalidateDayPanel, t]);

  const handleRescheduleTask = useCallback(async (taskId: string, newTime: string, oldTime: string | null) => {
    try {
      await updateTask(taskId, buildDueTimePatch({ due_date: null, due_time: oldTime }, newTime, date));
      invalidateDayPanel();
      toast.success(
        `${t('calendar.rescheduled')} -> ${newTime}`,
        oldTime
          ? {
              label: t('common.undo'),
              onClick: async () => {
                try {
                  await updateTask(taskId, { due_date: date, due_time: oldTime });
                  invalidateDayPanel();
                } catch (undoError) {
                  reportCalendarTaskActionError('day.undoReschedule', undoError, taskId);
                  toast.errorWithDetail(undoError, t('common.error'));
                }
              },
            }
          : undefined,
      );
    } catch (error) {
      reportCalendarTaskActionError('day.reschedule', error, taskId);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [date, invalidateDayPanel, t]);

  const handleResizeTask = useCallback(async (taskId: string, newMinutes: number, oldMinutes: number | null) => {
    try {
      await updateTask(taskId, { estimated_minutes: newMinutes });
      invalidateDayPanel();
      toast.success(
        `${t('calendar.resized')} -> ${newMinutes} ${t('common.min')}`,
        oldMinutes != null
          ? {
              label: t('common.undo'),
              onClick: async () => {
                try {
                  await updateTask(taskId, { estimated_minutes: oldMinutes });
                  invalidateDayPanel();
                } catch (undoError) {
                  reportCalendarTaskActionError('day.undoResize', undoError, taskId);
                  toast.errorWithDetail(undoError, t('common.error'));
                }
              },
            }
          : undefined,
      );
    } catch (error) {
      reportCalendarTaskActionError('day.resize', error, taskId);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [invalidateDayPanel, t]);

  const handleAddTask = useCallback(async (title: string) => {
    const trimmed = title.trim();
    if (!trimmed || addingTask) return false;
    setAddingTask(true);
    try {
      await quickCapture({ title: trimmed, dueDate: date });
      invalidateDayPanel();
      return true;
    } catch (error) {
      reportCalendarTaskActionError('day.addTask', error, date);
      toast.errorWithDetail(error, t('common.error'));
      return false;
    } finally {
      setAddingTask(false);
    }
  }, [addingTask, date, invalidateDayPanel, t]);

  return {
    addingTask,
    handleAddTask,
    handleComplete,
    handleReopen,
    handleRescheduleTask,
    handleResizeTask,
  };
}
