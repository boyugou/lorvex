import { useCallback } from 'react';

import { reportClientError } from '@/lib/errors/errorLogging';
import { openMainQuickCapture, openMainTaskDetail } from '@/lib/ipc/runtime';
import { deferTaskUntil } from '@/lib/ipc/tasks/mutations/deferral';
import { completeTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { DEFER_REASON_NOT_TODAY } from '@lorvex/shared/types';
import { getNextMondayYmd } from '@/lib/dayContextMath';
import { useI18n } from '@/lib/i18n';
import { toast } from '@/lib/notifications/toast';
import { addDays } from '@/components/calendar/calendarViewUtils';
import type { UsePopoverWindowActionsArgs } from './types';

export function usePopoverWindowActions({
  completingTaskIds,
  loadSummary,
  nextUpTasks,
  popoverMountedRef,
  requestHidePopover,
  setCompletingTaskIds,
  setDeferringTaskIds,
  deferringTaskIds,
  todayYmd,
  timezone,
}: UsePopoverWindowActionsArgs) {
  const { t } = useI18n();
  const handleQuickCapture = useCallback(async () => {
    try {
      await openMainQuickCapture();
      await requestHidePopover();
    } catch (error) {
      reportClientError('popover.quickCapture', 'Failed to open quick capture', error);
      toast.errorWithDetail(error, t('common.error'));
    }
  }, [requestHidePopover, t]);

  const handleOpenTask = useCallback((taskId: string) => {
    openMainTaskDetail(taskId)
      .then(() => {
        void requestHidePopover();
      })
      .catch((error) => {
        reportClientError('popover.openTask', 'Failed to open task from popover', error);
        toast.errorWithDetail(error, t('common.error'));
      });
  }, [requestHidePopover, t]);

  const handleCompleteTask = useCallback(async (taskId: string) => {
    if (completingTaskIds.includes(taskId)) return;
    setCompletingTaskIds((current) => [...current, taskId]);
    try {
      await completeTask(taskId);
      await loadSummary(false);
    } catch (error) {
      reportClientError('popover.completeTask', 'Failed to complete task from popover', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (popoverMountedRef.current) {
        setCompletingTaskIds((current) => current.filter((id) => id !== taskId));
      }
    }
  }, [completingTaskIds, loadSummary, popoverMountedRef, setCompletingTaskIds, t]);

  const handleDeferTask = useCallback(async (taskId: string) => {
    if (deferringTaskIds.includes(taskId)) return;
    setDeferringTaskIds((current) => [...current, taskId]);
    try {
      const tomorrow = addDays(todayYmd, 1);
      await deferTaskUntil(taskId, tomorrow, DEFER_REASON_NOT_TODAY);
      await loadSummary(false);
    } catch (error) {
      reportClientError('popover.deferTaskUntil', 'Failed to defer task from popover', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (popoverMountedRef.current) {
        setDeferringTaskIds((current) => current.filter((id) => id !== taskId));
      }
    }
  }, [loadSummary, popoverMountedRef, setDeferringTaskIds, deferringTaskIds, todayYmd, t]);

  const handleDeferTaskNextWeek = useCallback(async (taskId: string) => {
    if (deferringTaskIds.includes(taskId)) return;
    setDeferringTaskIds((current) => [...current, taskId]);
    try {
      const nextMonday = getNextMondayYmd(timezone);
      await deferTaskUntil(taskId, nextMonday, DEFER_REASON_NOT_TODAY);
      await loadSummary(false);
    } catch (error) {
      reportClientError('popover.deferTaskNextWeek', 'Failed to defer task to next week from popover', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (popoverMountedRef.current) {
        setDeferringTaskIds((current) => current.filter((id) => id !== taskId));
      }
    }
  }, [loadSummary, popoverMountedRef, setDeferringTaskIds, deferringTaskIds, timezone, t]);

  const handleOpenMain = useCallback(() => {
    const firstTask = nextUpTasks[0];
    if (firstTask) {
      handleOpenTask(firstTask.id);
      return;
    }
    void handleQuickCapture();
  }, [handleOpenTask, handleQuickCapture, nextUpTasks]);

  return {
    handleCompleteTask,
    handleOpenMain,
    handleOpenTask,
    handleQuickCapture,
    handleDeferTask,
    handleDeferTaskNextWeek,
  };
}
