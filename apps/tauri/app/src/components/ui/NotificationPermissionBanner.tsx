import { useCallback, useState } from 'react';
import { openUrl } from '@tauri-apps/plugin-opener';

import type { TranslationKey } from '@/lib/i18n';
import { reportClientError } from '@/lib/errors/errorLogging';
import { getDesktopPlatform } from '@/lib/platform/platform';
import { Banner } from '@/components/ui/Banner';
import { Button } from '@/components/ui/Button';
import {
  persistNotificationPermissionBannerDismissed,
  readNotificationPermissionBannerDismissed,
} from './NotificationPermissionBanner.runtime';

interface NotificationPermissionBannerProps {
  t: (key: TranslationKey) => string;
  onRequestAgain: () => Promise<void>;
}

/**
 * Reminders / habit / at-risk features silently no-op when the OS
 * notification permission is denied. This banner surfaces that
 * state so the user is not left to discover the feature is broken
 * only when they miss an important reminder.
 *
 * Renders under the top nav when `useNotificationPermissionStatus`
 * reports `promptedButDenied`. The primary action re-requests the
 * OS permission; macOS only shows the system dialog once per app
 * install, so if that returns denied immediately we fall back to
 * opening System Settings at the Notifications pane via
 * `x-apple.systempreferences:`.
 *
 * Session-dismissible via the runtime storage seam so the user isn't
 * nagged across every navigation during one session, but the banner
 * re-appears on next launch — the underlying problem is still real.
 */
export function NotificationPermissionBanner({
  t,
  onRequestAgain,
}: NotificationPermissionBannerProps) {
  const [dismissed, setDismissed] = useState(readNotificationPermissionBannerDismissed);

  const handleDismiss = useCallback(() => {
    setDismissed(true);
    persistNotificationPermissionBannerDismissed();
  }, []);

  const [requesting, setRequesting] = useState(false);
  const handleRequest = useCallback(async () => {
    setRequesting(true);
    try {
      await onRequestAgain();
    } finally {
      setRequesting(false);
    }
  }, [onRequestAgain]);

  const handleOpenSettings = useCallback(async () => {
    const platform = getDesktopPlatform();
    // macOS: jump straight to the Notifications pane.
    // Other platforms: fall back to a generic page the user can
    // navigate from. Windows lacks a stable x-* URL scheme that's
    // guaranteed across versions; the generic `ms-settings:notifications`
    // exists on modern Windows but opens only the settings app shell.
    const url =
      platform === 'macos'
        ? 'x-apple.systempreferences:com.apple.preference.notifications'
        : platform === 'windows'
          ? 'ms-settings:notifications'
          : null;
    if (!url) return;
    try {
      await openUrl(url);
    } catch (error) {
      reportClientError(
        'notifications.permission.openSettings',
        'Failed to open system notification settings',
        error,
        undefined,
        'warn',
      );
    }
  }, []);

  if (dismissed) return null;

  return (
    <Banner
      tone="warning"
      actions={
        <>
          <Button
            variant="primary"
            size="banner"
            onClick={() => { void handleRequest(); }}
            disabled={requesting}
          >
            {requesting ? t('common.loading') : t('notifications.permissionBannerRetry')}
          </Button>
          <Button
            variant="outline"
            onClick={() => { void handleOpenSettings(); }}
            disabled={requesting}
          >
            {t('notifications.permissionBannerOpenSettings')}
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={handleDismiss}
            aria-label={t('common.dismiss')}
          >
            {/* hide the ×-glyph from AT. Without
                `aria-hidden="true"` JAWS/NVDA read U+00D7 as
                "multiplication sign", which collides with the real
                `aria-label` ("Dismiss") on the button. */}
            <span aria-hidden="true">×</span>
          </Button>
        </>
      }
    >
      {t('notifications.permissionBannerMessage')}
    </Banner>
  );
}
