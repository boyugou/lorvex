import type { NotificationSendResult } from './runtime.logic';

export type PermissionCache = true | false | null;

export interface NotificationOptions {
  title: string;
  body?: string;
  actionTypeId?: string;
  extra?: Record<string, string>;
}

export interface NotificationPlugin {
  isPermissionGranted: () => Promise<boolean>;
  sendNotification: (options: NotificationOptions & { silent: boolean }) => void;
}

export interface NotificationPermissionCacheState {
  current: PermissionCache;
}

interface SendNotificationRuntimeDeps {
  cacheState: NotificationPermissionCacheState;
  getSoundEnabled: () => Promise<boolean>;
  isInQuietHours: () => Promise<boolean>;
  loadNotificationPlugin: () => Promise<NotificationPlugin>;
  options: NotificationOptions;
  reportDispatchError: (error: unknown) => void;
  reportPermissionDenied: (error: unknown) => void;
}

interface VisibilityRefreshRuntimeDeps {
  addVisibilityListener: ((handler: () => void) => void) | null;
  getVisibilityState: () => DocumentVisibilityState;
  refreshPermissionCache: () => void;
}

type NotificationPermissionVisibilityRefreshHost = Pick<
  VisibilityRefreshRuntimeDeps,
  'addVisibilityListener' | 'getVisibilityState'
>;

export function createBrowserNotificationPermissionVisibilityRefreshHost(): NotificationPermissionVisibilityRefreshHost {
  return {
    addVisibilityListener: typeof document === 'undefined'
      ? null
      : (handler) => {
          document.addEventListener('visibilitychange', handler);
        },
    getVisibilityState: () => (typeof document === 'undefined' ? 'visible' : document.visibilityState),
  };
}

export function refreshNotificationPermissionCacheState(
  cacheState: NotificationPermissionCacheState,
): void {
  cacheState.current = null;
}

export function installNotificationPermissionVisibilityRefreshRuntime(
  deps: VisibilityRefreshRuntimeDeps,
): void {
  if (!deps.addVisibilityListener) return;

  deps.addVisibilityListener(() => {
    if (deps.getVisibilityState() === 'visible') {
      deps.refreshPermissionCache();
    }
  });
}

export async function sendNotificationRuntime(
  deps: SendNotificationRuntimeDeps,
): Promise<NotificationSendResult> {
  if (deps.cacheState.current === false) return 'suppressed_permission';
  try {
    if (await deps.isInQuietHours()) return 'suppressed_quiet_hours';
    const notification = await deps.loadNotificationPlugin();
    if (deps.cacheState.current === null) {
      try {
        deps.cacheState.current = await notification.isPermissionGranted();
      } catch {
        // Probe failure — let the send attempt below decide.
      }
      if (deps.cacheState.current === false) return 'suppressed_permission';
    }
    const soundEnabled = await deps.getSoundEnabled();
    notification.sendNotification({
      title: deps.options.title,
      ...(deps.options.body != null && { body: deps.options.body }),
      ...(deps.options.actionTypeId != null && { actionTypeId: deps.options.actionTypeId }),
      ...(deps.options.extra != null && { extra: deps.options.extra }),
      silent: !soundEnabled,
    });
    return 'sent';
  } catch (error) {
    try {
      const notification = await deps.loadNotificationPlugin();
      const granted = await notification.isPermissionGranted();
      if (!granted) {
        deps.cacheState.current = false;
        deps.reportPermissionDenied(error);
        return 'suppressed_permission';
      }
    } catch {
      // Probe failed; fall through to generic error reporting.
    }
    deps.reportDispatchError(error);
    return 'failed';
  }
}
