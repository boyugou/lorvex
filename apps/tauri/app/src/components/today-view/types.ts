import type { DayContext } from '@/lib/dayContext';
import type { TranslationKey } from '@/lib/i18n';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { DashboardLayout } from '@/lib/ipc/dashboard';
import type { CurrentFocusWithTasks, FocusScheduleWithTasks, Overview, Task } from '@/lib/ipc/tasks/models';
import type { View } from '@/lib/types';

export interface TodayViewProps {
  overview: Overview | null;
  onNavigate?: ((view: View) => void) | undefined;
  onSelectTask?: ((taskId: string) => void) | undefined;
  /**
   * AllClearView's primary "+ Add task" CTA. Threaded from
   * MainViewContent's `openQuickCaptureNoArgs` so the empty-Today state
   * offers a one-click capture path instead of forcing the user to
   * remember the cmd+N shortcut or hunt for the FAB.
   */
  onAddTask?: (() => void) | undefined;
}

export interface UseTodayViewControllerArgs extends TodayViewProps {
  dayContext: DayContext;
  usesMobileLayout: boolean;
}

export interface TodayViewContentProps {
  todayPoolTasks: Task[];
  greeting: string;
  hasPlanTasks: boolean;
  hasRecoverableTodayError: boolean;
  isAiLayout: boolean;
  isFirstRun: boolean;
  isTodayLoading: boolean;
  onNavigate?: ((view: View) => void) | undefined;
  onSelectTask?: ((taskId: string) => void) | undefined;
  onAddTask?: (() => void) | undefined;
  overdueTasks: Task[];
  overview: Overview | null;
  plan: CurrentFocusWithTasks | null | undefined;
  focusSchedule: FocusScheduleWithTasks | null;
  sections: DashboardLayout['sections'];
  somedayTasks: Task[];
  stats: Overview['stats'] | undefined;
  t: (key: TranslationKey) => string;
  today: string;
  todayIso: string;
  todayEvents: UnifiedCalendarEvent[];
  upcomingWeekTasks: Task[];
  refetchFailedTodayQueries: () => void;
}
