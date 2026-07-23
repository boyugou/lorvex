import { resolveConfiguredTimezoneState } from '@/lib/dayContext';
import { isValidTimezone } from '@/lib/dates/timezone';

type TimezoneMaintenanceAction =
  | { type: 'noop' }
  | { type: 'seed'; timezone: string }
  | { type: 'repair'; timezone: string }
  | { type: 'update'; previousTimezone: string; timezone: string };

export function decideTimezoneMaintenance(
  storedPreference: string | null,
  systemTimezone: string | null,
): TimezoneMaintenanceAction {
  if (!isValidTimezone(systemTimezone)) {
    return { type: 'noop' };
  }

  if (storedPreference === null) {
    return {
      type: 'seed',
      timezone: systemTimezone,
    };
  }

  const resolved = resolveConfiguredTimezoneState(storedPreference);
  if (resolved.invalidStoredPreference) {
    return {
      type: 'repair',
      timezone: systemTimezone,
    };
  }

  if (resolved.timezone !== systemTimezone) {
    return {
      type: 'update',
      previousTimezone: resolved.timezone,
      timezone: systemTimezone,
    };
  }

  return { type: 'noop' };
}
