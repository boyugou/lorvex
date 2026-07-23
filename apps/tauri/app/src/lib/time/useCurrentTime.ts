import { useCallback, useEffect, useState } from 'react';

import { useVisibilityGatedInterval } from './useVisibilityGatedInterval';
import { addMinutesToTime } from './useCurrentTime.logic';
import { readCurrentTimeValue, reconcileCurrentTimeValue } from './useCurrentTime.runtime';

/**
 * Returns the current time as "HH:MM", updating every 60 seconds.
 * If a timezone is provided, returns the time in that timezone;
 * otherwise falls back to the system local time.
 */
export function useCurrentTime(timezone?: string): string {
  const [time, setTime] = useState(() => readCurrentTimeValue(timezone));
  // gate the 60s clock tick on visibility. With many
  // components (sidebar clock, popover, event items, focus overlay)
  // depending on this value, a naive setInterval re-rendered the
  // full subtree every minute even when the window was hidden. The
  // catch-up tick on visibility → visible also fixes the macOS-sleep
  // drift where the displayed minute lagged by up to 60s after wake.
  const tick = useCallback(() => {
    setTime(readCurrentTimeValue(timezone));
  }, [timezone]);
  useVisibilityGatedInterval(tick, 60_000);

  useEffect(() => {
    setTime((current) => reconcileCurrentTimeValue(current, timezone));
  }, [timezone]);

  return time;
}

/**
 * Returns true if a calendar event's time range is entirely in the past
 * relative to the given `nowHHMM` string.
 * All-day events are never considered past.
 */
export function isEventPast(
  event: { all_day?: boolean | number; start_time?: string | null; end_time?: string | null },
  nowHHMM: string,
): boolean {
  if (event.all_day) return false;
  if (!event.start_time) return false;
  // Use end_time if available, otherwise start_time + 60min
  const endStr = event.end_time || addMinutesToTime(event.start_time, 60);
  return endStr <= nowHHMM;
}
