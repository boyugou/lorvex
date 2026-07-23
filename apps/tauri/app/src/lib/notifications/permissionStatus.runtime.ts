interface NotificationPermissionStatusPlugin {
  isPermissionGranted: () => Promise<boolean>;
  requestPermission: () => Promise<'granted' | 'denied' | 'default'>;
}

interface ProbeNotificationPermissionStatusRuntimeDeps {
  getPersistedGranted: () => Promise<boolean>;
  getPrompted: () => Promise<boolean>;
  loadNotificationPlugin: () => Promise<NotificationPermissionStatusPlugin>;
  refreshNotificationPermissionCache: () => void;
  reportProbeError: (error: unknown) => void;
  reportRevokedWhileRunning: () => void;
  setPersistedGranted: (granted: boolean) => Promise<void>;
  setPromptedButDenied: (value: boolean) => void;
}

interface RequestNotificationPermissionAgainRuntimeDeps {
  loadNotificationPlugin: () => Promise<NotificationPermissionStatusPlugin>;
  refreshNotificationPermissionCache: () => void;
  reportRequestError: (error: unknown) => void;
  setPersistedGranted: (granted: boolean) => Promise<void>;
  setPromptedButDenied: (value: boolean) => void;
}

interface NotificationPermissionStatusWatchRuntimeDeps {
  addVisibilityListener: ((handler: () => void) => () => void) | null;
  addWindowFocusListener: ((handler: () => void) => () => void) | null;
  enabled: boolean;
  probe: () => Promise<void>;
  reportWatchError: (error: unknown) => void;
}

type NotificationPermissionStatusWatchHost = Pick<
  NotificationPermissionStatusWatchRuntimeDeps,
  'addVisibilityListener' | 'addWindowFocusListener'
>;

export function createBrowserNotificationPermissionStatusWatchHost(): NotificationPermissionStatusWatchHost {
  return {
    addVisibilityListener: typeof document === 'undefined'
      ? null
      : (handler) => {
          document.addEventListener('visibilitychange', handler);
          return () => document.removeEventListener('visibilitychange', handler);
        },
    addWindowFocusListener: typeof window === 'undefined'
      ? null
      : (handler) => {
          window.addEventListener('focus', handler);
          return () => window.removeEventListener('focus', handler);
        },
  };
}

export async function probeNotificationPermissionStatusRuntime(
  deps: ProbeNotificationPermissionStatusRuntimeDeps,
): Promise<void> {
  try {
    deps.refreshNotificationPermissionCache();
    const prompted = await deps.getPrompted();
    if (!prompted) {
      deps.setPromptedButDenied(false);
      return;
    }
    const notification = await deps.loadNotificationPlugin();
    const grantedNow = await notification.isPermissionGranted();
    const grantedPersisted = await deps.getPersistedGranted();
    if (grantedNow !== grantedPersisted) {
      await deps.setPersistedGranted(grantedNow);
      if (grantedPersisted && !grantedNow) {
        deps.reportRevokedWhileRunning();
      }
    }
    deps.setPromptedButDenied(!grantedNow);
  } catch (error) {
    deps.reportProbeError(error);
  }
}

export async function requestNotificationPermissionAgainRuntime(
  deps: RequestNotificationPermissionAgainRuntimeDeps,
): Promise<void> {
  try {
    const notification = await deps.loadNotificationPlugin();
    const response = await notification.requestPermission();
    const granted = response === 'granted';
    deps.refreshNotificationPermissionCache();
    await deps.setPersistedGranted(granted);
    deps.setPromptedButDenied(!granted);
  } catch (error) {
    deps.reportRequestError(error);
  }
}

export function installNotificationPermissionStatusWatchRuntime(
  deps: NotificationPermissionStatusWatchRuntimeDeps,
): () => void {
  if (!deps.enabled) return () => {};

  let cancelled = false;
  const runProbe = () => {
    if (!cancelled) {
      void Promise.resolve()
        .then(() => (cancelled ? undefined : deps.probe()))
        .catch((error: unknown) => {
          if (!cancelled) {
            deps.reportWatchError(error);
          }
        });
    }
  };

  runProbe();
  const removeWindowFocus = deps.addWindowFocusListener
    ? deps.addWindowFocusListener(runProbe)
    : () => {};
  const removeVisibility = deps.addVisibilityListener
    ? deps.addVisibilityListener(runProbe)
    : () => {};

  return () => {
    cancelled = true;
    removeWindowFocus();
    removeVisibility();
  };
}
