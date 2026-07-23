import type { DashboardLayout } from '@/lib/ipc/dashboard';

type DashboardSections = DashboardLayout['sections'];

export interface TodayViewRefreshDelayTimerHost {
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export const TODAY_VIEW_PULL_TO_REFRESH_FEEDBACK_DELAY_MS = 600;

export function createBrowserTodayViewRefreshDelayTimerHost(): TodayViewRefreshDelayTimerHost {
  return {
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function waitForTodayViewPullToRefreshFeedback({
  timerHost,
  delayMs = TODAY_VIEW_PULL_TO_REFRESH_FEEDBACK_DELAY_MS,
}: {
  timerHost: TodayViewRefreshDelayTimerHost;
  delayMs?: number;
}): Promise<void> {
  return new Promise((resolve) => {
    timerHost.setTimeout(resolve, delayMs);
  });
}

export function mergeCanonicalOverdueSection(
  sections: DashboardSections,
  overdueTaskCount: number,
): DashboardSections {
  if (overdueTaskCount <= 0) return sections;
  if (sections.some((section) => section.type === 'overdue_alert')) return sections;
  return [{ type: 'overdue_alert' }, ...sections];
}
