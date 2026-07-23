import { useCallback, useEffect } from 'react';
import { useI18n } from '@/lib/i18n';
import { useLazyRef } from '@/lib/useLazyRef';
import {
  cleanupDangerZoneLinkFocus,
  createBrowserDangerZoneLinkTimerHost,
  createDangerZoneLinkRuntimeState,
  scheduleDangerZoneLinkFocus,
} from './dangerZoneLink.runtime';

/** Target id matches the wrapper in DataSettingsSection. Keep in sync. */
const DANGER_ZONE_SECTION_ID = 'settings-section-danger-zone';

/**
 * when a destructive action moved from a feature panel
 * into the Danger Zone, leave this hint behind so discoverability
 * isn't regressed. Clicking scrolls to (and focuses) the Danger Zone
 * section a few rows below in the same view.
 */
export function DangerZoneLink({ message }: { message: string }) {
  const { t } = useI18n();
  const runtimeStateRef = useLazyRef(() => createDangerZoneLinkRuntimeState());
  const timerHostRef = useLazyRef(() => createBrowserDangerZoneLinkTimerHost());

  const handleClick = useCallback(() => {
    const el = document.getElementById(DANGER_ZONE_SECTION_ID);
    if (!el) return;
    // Give the scroll a moment before focusing the heading so screen
    // readers announce the new location after the viewport settles.
    scheduleDangerZoneLinkFocus({
      delayMs: 300,
      state: runtimeStateRef.current,
      target: el,
      timerHost: timerHostRef.current,
    });
    // *Ref values are stable MutableRefObjects from useLazyRef.
  }, [runtimeStateRef, timerHostRef]);

  useEffect(() => () => {
    cleanupDangerZoneLinkFocus(runtimeStateRef.current, timerHostRef.current);
    // *Ref values are stable MutableRefObjects from useLazyRef.
  }, [runtimeStateRef, timerHostRef]);

  return (
    <p className="text-2xs text-text-muted leading-snug">
      {message}{' '}
      <button
        type="button"
        onClick={handleClick}
        className="underline decoration-dotted underline-offset-2 text-text-secondary hover:text-accent focus-ring-soft rounded-r-control"
      >
        {t('settings.goToDangerZone')}
      </button>
    </p>
  );
}
