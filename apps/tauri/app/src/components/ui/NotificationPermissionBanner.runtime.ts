const DISMISS_SESSION_KEY = 'lorvex.notif_permission_banner_dismissed.v1';

type DismissStorage = Pick<Storage, 'getItem' | 'setItem'>;

function resolveDismissStorage(): DismissStorage | null {
  try {
    return globalThis.sessionStorage ?? null;
  } catch {
    return null;
  }
}

export function readNotificationPermissionBannerDismissed(
  storage: DismissStorage | null = resolveDismissStorage(),
): boolean {
  try {
    return storage?.getItem(DISMISS_SESSION_KEY) === '1';
  } catch {
    return false;
  }
}

export function persistNotificationPermissionBannerDismissed(
  storage: DismissStorage | null = resolveDismissStorage(),
): void {
  try {
    storage?.setItem(DISMISS_SESSION_KEY, '1');
  } catch {
    // Quota/private-mode failures are non-fatal; the banner may reappear next mount.
  }
}
