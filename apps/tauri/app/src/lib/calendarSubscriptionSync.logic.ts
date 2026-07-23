import { HOUR_MS } from '@/lib/time/durations';

/** How often to sync calendar subscriptions (60 minutes). */
export const SUBSCRIPTION_SYNC_INTERVAL_MS = HOUR_MS;

/**
 * Initial sync on mount is delayed to avoid competing with app startup.
 */
export const SUBSCRIPTION_SYNC_INITIAL_DELAY_MS = 10_000;

export const SUBSCRIPTION_SYNC_MIN_GAP_MS = 30 * 1000;

interface CalendarSubscriptionSyncHost {
  isOnline: () => boolean;
  now: () => number;
  performSync: () => Promise<unknown>;
  reportError: (error: unknown) => void;
}

export interface CalendarSubscriptionSyncController {
  getLastAttemptAt: () => number | null;
  handleConnectionChange: () => Promise<boolean>;
  handleOnline: () => Promise<boolean>;
  isSyncing: () => boolean;
  trySync: () => Promise<boolean>;
}

export function createCalendarSubscriptionSyncController(
  host: CalendarSubscriptionSyncHost,
): CalendarSubscriptionSyncController {
  let syncing = false;
  let lastAttemptAt: number | null = null;

  const trySync = async (): Promise<boolean> => {
    if (syncing) return false;
    if (!host.isOnline()) return false;
    const now = host.now();
    if (lastAttemptAt !== null && now - lastAttemptAt < SUBSCRIPTION_SYNC_MIN_GAP_MS) return false;

    lastAttemptAt = now;
    syncing = true;
    try {
      await host.performSync();
    } catch (error) {
      host.reportError(error);
    } finally {
      syncing = false;
    }
    return true;
  };

  return {
    trySync,
    handleOnline: () => trySync(),
    handleConnectionChange: () => {
      if (!host.isOnline()) return Promise.resolve(false);
      return trySync();
    },
    isSyncing: () => syncing,
    getLastAttemptAt: () => lastAttemptAt,
  };
}
