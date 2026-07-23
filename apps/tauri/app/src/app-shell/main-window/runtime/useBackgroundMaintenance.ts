import { useEffect } from 'react';

import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { getPreference, setPreference } from '@/lib/ipc/settings';
import { PREF_TIMEZONE } from '@/lib/preferences/keys';
import { getRawSystemTimezone } from '@/lib/dates/timezone';
import { toast } from '@/lib/notifications/toast';
import { decideTimezoneMaintenance } from './useBackgroundMaintenance.logic';
import {
  createBrowserBackgroundMaintenanceTimerHost,
  installBackgroundMaintenanceLoop,
} from './useBackgroundMaintenance.runtime';

const TIMEZONE_CHECK_INTERVAL_MS = 60_000;
const backgroundMaintenanceTimerHost = createBrowserBackgroundMaintenanceTimerHost();

interface UseBackgroundMaintenanceOptions {
  monitorTimezone: boolean;
}

export function useBackgroundMaintenance({
  monitorTimezone,
}: UseBackgroundMaintenanceOptions) {
  const { format } = useI18n();

  // Seed timezone on first run, then periodically detect timezone drift.
  useEffect(() => {
    if (!monitorTimezone) return;
    let cancelled = false;
    const cleanup = installBackgroundMaintenanceLoop({
      delayMs: TIMEZONE_CHECK_INTERVAL_MS,
      run: async () => {
        if (cancelled) return;
        const systemTz = getRawSystemTimezone();
        const stored = await getPreference(PREF_TIMEZONE);
        if (cancelled) return;

        const action = decideTimezoneMaintenance(stored, systemTz);
        if (action.type === 'seed' || action.type === 'repair') {
          await setPreference(PREF_TIMEZONE, action.timezone);
        } else if (action.type === 'update') {
          await setPreference(PREF_TIMEZONE, action.timezone);
          toast.info(
            format('settings.timezoneAutoUpdated', {
              '0': action.previousTimezone,
              '1': action.timezone,
            }),
          );
        }
      },
      onError: (error) => {
        reportClientError('app.timezone.drift', 'Timezone change check failed', error);
      },
      timerHost: backgroundMaintenanceTimerHost,
    });
    return () => {
      cancelled = true;
      cleanup();
    };
  }, [monitorTimezone, format]);
}
