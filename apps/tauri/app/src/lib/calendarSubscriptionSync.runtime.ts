import type { createCalendarSubscriptionSyncController } from './calendarSubscriptionSync.logic';

type CalendarSubscriptionSyncController = ReturnType<typeof createCalendarSubscriptionSyncController>;

interface CalendarSubscriptionSyncRuntimeDeps {
  controller: Pick<
    CalendarSubscriptionSyncController,
    'trySync' | 'handleOnline' | 'handleConnectionChange'
  >;
  initialDelayMs: number;
  intervalMs: number;
  windowTarget?: Pick<Window, 'addEventListener' | 'removeEventListener'> | null;
  connectionTarget:
    | {
        addEventListener?: ((type: 'change', listener: () => void) => void) | undefined;
        removeEventListener?: ((type: 'change', listener: () => void) => void) | undefined;
      }
    | null
    | undefined;
  setTimeout: typeof globalThis.setTimeout;
  clearTimeout: typeof globalThis.clearTimeout;
  setInterval: typeof globalThis.setInterval;
  clearInterval: typeof globalThis.clearInterval;
}

type CalendarSubscriptionSyncBrowserRuntimeInput = Pick<
  CalendarSubscriptionSyncRuntimeDeps,
  'controller' | 'initialDelayMs' | 'intervalMs'
>;

export function readCalendarSubscriptionBrowserOnlineStatus(): boolean {
  try {
    return globalThis.navigator?.onLine !== false;
  } catch {
    return true;
  }
}

export function createBrowserCalendarSubscriptionSyncRuntimeDeps(
  input: CalendarSubscriptionSyncBrowserRuntimeInput,
): CalendarSubscriptionSyncRuntimeDeps {
  return {
    ...input,
    windowTarget: readBrowserWindowTarget(),
    connectionTarget: readBrowserConnectionTarget(),
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
    clearTimeout: (handle) => globalThis.clearTimeout(handle),
    setInterval: (callback, delayMs) => globalThis.setInterval(callback, delayMs),
    clearInterval: (handle) => globalThis.clearInterval(handle),
  };
}

export function startCalendarSubscriptionSyncRuntime(
  deps: CalendarSubscriptionSyncRuntimeDeps,
): () => void {
  const {
    controller,
    initialDelayMs,
    intervalMs,
    windowTarget,
    connectionTarget,
  } = deps;
  const timerHost = deps;

  const initialTimeout = timerHost.setTimeout(() => {
    void controller.trySync();
  }, initialDelayMs);

  const interval = timerHost.setInterval(() => {
    void controller.trySync();
  }, intervalMs);

  const onOnline = () => {
    void controller.handleOnline();
  };
  windowTarget?.addEventListener('online', onOnline);

  const onConnectionChange = () => {
    void controller.handleConnectionChange();
  };
  connectionTarget?.addEventListener?.('change', onConnectionChange);

  return () => {
    timerHost.clearTimeout(initialTimeout);
    timerHost.clearInterval(interval);
    windowTarget?.removeEventListener('online', onOnline);
    connectionTarget?.removeEventListener?.('change', onConnectionChange);
  };
}

function readBrowserWindowTarget(): Pick<Window, 'addEventListener' | 'removeEventListener'> | null {
  try {
    const target = globalThis.window;
    return typeof target?.addEventListener === 'function'
      && typeof target?.removeEventListener === 'function'
      ? target
      : null;
  } catch {
    return null;
  }
}

function readBrowserConnectionTarget(): CalendarSubscriptionSyncRuntimeDeps['connectionTarget'] {
  try {
    return (globalThis.navigator as Navigator & {
      connection?: CalendarSubscriptionSyncRuntimeDeps['connectionTarget'];
    } | undefined)?.connection;
  } catch {
    return null;
  }
}
