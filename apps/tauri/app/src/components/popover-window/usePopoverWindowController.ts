import { useConfiguredDayContext } from '@/lib/dayContext';
import { useI18n } from '@/lib/i18n';
import { useExternalMutationSubscription } from '@/lib/useExternalMutationSubscription';

import { usePopoverWindowActions } from './controller/actions';
import { usePopoverWindowLifecycle } from './controller/lifecycle';
import { usePopoverSummary } from './controller/summary';
import type { PopoverWindowControllerState } from './controller/types';

export type { PopoverWindowControllerState } from './controller/types';

export function usePopoverWindowController(): PopoverWindowControllerState {
  useExternalMutationSubscription();
  const { t, locale } = useI18n();
  const dayContext = useConfiguredDayContext();
  const summary = usePopoverSummary({ dayContext, t });
  const { requestHidePopover } = usePopoverWindowLifecycle({
    loadSummary: summary.loadSummary,
  });
  const actions = usePopoverWindowActions({
    completingTaskIds: summary.completingTaskIds,
    loadSummary: summary.loadSummary,
    nextUpTasks: summary.nextUpTasks,
    popoverMountedRef: summary.popoverMountedRef,
    requestHidePopover,
    setCompletingTaskIds: summary.setCompletingTaskIds,
    setDeferringTaskIds: summary.setDeferringTaskIds,
    deferringTaskIds: summary.deferringTaskIds,
    timezone: dayContext.timezone,
    todayYmd: dayContext.todayYmd,
  });

  return {
    briefing: summary.briefing,
    completingTaskIds: summary.completingTaskIds,
    handleCompleteTask: actions.handleCompleteTask,
    handleOpenMain: actions.handleOpenMain,
    handleOpenTask: actions.handleOpenTask,
    handleQuickCapture: actions.handleQuickCapture,
    handleDeferTask: actions.handleDeferTask,
    handleDeferTaskNextWeek: actions.handleDeferTaskNextWeek,
    isLoading: summary.isLoading,
    locale,
    nextUpTasks: summary.nextUpTasks,
    overdueCount: summary.overdueCount,
    planCount: summary.planCount,
    deferringTaskIds: summary.deferringTaskIds,
    t,
    attentionCount: summary.attentionCount,
    todayEvents: summary.todayEvents,
    todayYmd: dayContext.todayYmd,
    timezone: dayContext.timezone,
  };
}
