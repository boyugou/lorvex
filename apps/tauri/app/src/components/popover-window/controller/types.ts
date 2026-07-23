import type { Dispatch, RefObject, SetStateAction } from 'react';

import type { DayContext } from '@/lib/dayContext';
import type { useI18n } from '@/lib/i18n';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';

export interface PopoverWindowControllerState {
  briefing: string;
  completingTaskIds: string[];
  handleCompleteTask: (taskId: string) => Promise<void>;
  handleOpenMain: () => void;
  handleOpenTask: (taskId: string) => void;
  handleQuickCapture: () => Promise<void>;
  handleDeferTask: (taskId: string) => Promise<void>;
  handleDeferTaskNextWeek: (taskId: string) => Promise<void>;
  isLoading: boolean;
  nextUpTasks: Task[];
  overdueCount: number;
  planCount: number;
  deferringTaskIds: string[];
  locale: string;
  t: ReturnType<typeof useI18n>['t'];
  attentionCount: number;
  todayEvents: UnifiedCalendarEvent[];
  todayYmd: string;
  timezone: string;
}

export interface PopoverSummaryState {
  briefing: string;
  completingTaskIds: string[];
  isLoading: boolean;
  loadSummary: (withLoadingState?: boolean) => Promise<void>;
  nextUpTasks: Task[];
  overdueCount: number;
  planCount: number;
  popoverMountedRef: RefObject<boolean>;
  setCompletingTaskIds: Dispatch<SetStateAction<string[]>>;
  setDeferringTaskIds: Dispatch<SetStateAction<string[]>>;
  deferringTaskIds: string[];
  attentionCount: number;
  todayEvents: UnifiedCalendarEvent[];
}

export interface UsePopoverSummaryArgs {
  dayContext: DayContext;
  t: ReturnType<typeof useI18n>['t'];
}

export interface UsePopoverWindowLifecycleArgs {
  loadSummary: (withLoadingState?: boolean) => Promise<void>;
}

export interface UsePopoverWindowActionsArgs {
  completingTaskIds: string[];
  loadSummary: (withLoadingState?: boolean) => Promise<void>;
  nextUpTasks: Task[];
  popoverMountedRef: RefObject<boolean>;
  requestHidePopover: () => Promise<void>;
  setCompletingTaskIds: Dispatch<SetStateAction<string[]>>;
  setDeferringTaskIds: Dispatch<SetStateAction<string[]>>;
  deferringTaskIds: string[];
  timezone: string;
  todayYmd: string;
}
