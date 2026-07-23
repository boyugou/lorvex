import { useEffect, useMemo, useState } from 'react';

import { usePreference } from './query/usePreference';
import { STALE_LONG } from './query/timing';
import { tryParsePreferenceJson } from './preferences/parser';
import { PREF_TIMEZONE } from './preferences/keys';
import { getSystemTimezone, isValidTimezone, normalizeTimezonePreference } from './dates/timezone';
import {
  addYmdDays,
  msUntilNextMidnightInTimezone,
  ymdFromDateParts,
} from './dayContextMath';
import {
  createBrowserDayContextRolloverRuntimeDeps,
  startDayContextRolloverRuntime,
} from './dayContextProvider.runtime';

export interface DayContext {
  timezone: string;
  todayYmd: string;
  tomorrowYmd: string;
}

export function useConfiguredTimezone(): { timezone: string } {
  const { value: timezone } = usePreference(
    PREF_TIMEZONE,
    resolveConfiguredTimezone,
    { staleTime: STALE_LONG },
  );

  return {
    timezone,
  };
}

interface ConfiguredTimezoneResolution {
  timezone: string;
  invalidStoredPreference: boolean;
}

export function resolveConfiguredTimezoneState(raw: string | null): ConfiguredTimezoneResolution {
  const systemTimezone = getSystemTimezone();
  const fallbackTimezone = normalizeTimezonePreference(null, systemTimezone);
  if (raw === null) {
    return {
      timezone: fallbackTimezone,
      invalidStoredPreference: false,
    };
  }
  const parsed = tryParsePreferenceJson(raw);

  if (!parsed.ok) {
    return {
      timezone: fallbackTimezone,
      invalidStoredPreference: true,
    };
  }

  if (parsed.value === null) {
    return {
      timezone: fallbackTimezone,
      invalidStoredPreference: true,
    };
  }

  return {
    timezone: normalizeTimezonePreference(parsed.value, systemTimezone),
    invalidStoredPreference: typeof parsed.value !== 'string' || !isValidTimezone(parsed.value),
  };
}

export function resolveConfiguredTimezone(raw: string | null): string {
  return resolveConfiguredTimezoneState(raw).timezone;
}

export function buildDayContext(
  timeZone: string,
  now: Date = new Date(),
): DayContext {
  const todayYmd = ymdFromDateParts(now, timeZone);
  return {
    timezone: timeZone,
    todayYmd,
    tomorrowYmd: addYmdDays(todayYmd, 1),
  };
}

export function useConfiguredDayContext(): DayContext {
  const { timezone } = useConfiguredTimezone();
  const [, forceMidnightRerender] = useState(0);
  useEffect(() => {
    return startDayContextRolloverRuntime(createBrowserDayContextRolloverRuntimeDeps({
      getCurrentYmd: () => ymdFromDateParts(new Date(), timezone),
      getDelayMs: () => msUntilNextMidnightInTimezone(timezone),
      onRollover: () => forceMidnightRerender((t) => t + 1),
    }));
  }, [timezone]);

  // Memoize on the (timezone, todayYmd) seed so consumers' `useMemo` /
  // `useEffect` dependency arrays stay stable across renders. 35+ files
  // use this hook; without memoization every one of them invalidates
  // cached derivations whenever their ancestor re-renders.
  //
  // Re-allocating on every render of every subscriber would also
  // ripple through `useConfiguredTimezone()` query subscriber fan-out;
  // the memo boundary keeps it to one allocation per timezone change
  // (plus one per local-day rollover observed via todayYmd).
  const todayYmd = ymdFromDateParts(new Date(), timezone);
  return useMemo(() => ({
    timezone,
    todayYmd,
    tomorrowYmd: addYmdDays(todayYmd, 1),
  }), [timezone, todayYmd]);
}

export function getRelativeDateYmd(
  timeZone: string,
  offsetDays: number,
  now: Date = new Date(),
): string {
  const today = ymdFromDateParts(now, timeZone);
  return addYmdDays(today, offsetDays);
}

export function getMinutesSinceMidnightInTimezone(
  timeZone: string,
  now: Date = new Date(),
): number {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  });
  const parts = formatter.formatToParts(now);
  const hour = Number(parts.find((part) => part.type === 'hour')?.value ?? '0');
  const minute = Number(parts.find((part) => part.type === 'minute')?.value ?? '0');
  return hour * 60 + minute;
}

export function getWeekdayNameInTimezone(
  timeZone: string,
  now: Date = new Date(),
): string {
  return new Intl.DateTimeFormat('en-US', {
    timeZone,
    weekday: 'long',
  }).format(now).toLowerCase();
}
