import { useEffect } from 'react';
import { syncAllCalendarSubscriptions } from './ipc/calendar';
import { reportClientError } from './errors/errorLogging';
import {
  createCalendarSubscriptionSyncController,
  SUBSCRIPTION_SYNC_INITIAL_DELAY_MS,
  SUBSCRIPTION_SYNC_INTERVAL_MS,
} from './calendarSubscriptionSync.logic';
import {
  createBrowserCalendarSubscriptionSyncRuntimeDeps,
  readCalendarSubscriptionBrowserOnlineStatus,
  startCalendarSubscriptionSyncRuntime,
} from './calendarSubscriptionSync.runtime';

/**
 * Background periodic sync for .ics calendar subscriptions.
 * Runs on mount + every 60 minutes when the browser reports online status.
 * An offline state skips the attempt entirely (rather than letting every
 * subscription flash a scary "fetch failed" red indicator) and retries on
 * the next `online` event (throttled by SUBSCRIPTION_SYNC_MIN_GAP_MS).
 * Errors during an online attempt are logged but don't interrupt the app.
 */
export function useCalendarSubscriptionSync() {
  useEffect(() => {
    const controller = createCalendarSubscriptionSyncController({
      isOnline: readCalendarSubscriptionBrowserOnlineStatus,
      now: () => Date.now(),
      performSync: () => syncAllCalendarSubscriptions(),
      reportError: (error) => {
        reportClientError(
          'calendarSubscriptionSync',
          'Background calendar subscription sync failed',
          error,
        );
      },
    });

    return startCalendarSubscriptionSyncRuntime(
      createBrowserCalendarSubscriptionSyncRuntimeDeps({
        controller,
        initialDelayMs: SUBSCRIPTION_SYNC_INITIAL_DELAY_MS,
        intervalMs: SUBSCRIPTION_SYNC_INTERVAL_MS,
      }),
    );
  }, []);
}
