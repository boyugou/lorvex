import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';

import { useConfiguredTimezone, type DayContext } from './dayContext';
import { addYmdDays, msUntilNextMidnightInTimezone, ymdFromDateParts } from './dayContextMath';
import {
  createBrowserDayContextRolloverRuntimeDeps,
  startDayContextRolloverRuntime,
} from './dayContextProvider.runtime';

const DayContextContext = createContext<DayContext | null>(null);

/**
 * Provides a single shared DayContext subscription for the entire app tree.
 *
 * Without this, every component that calls `useConfiguredDayContext()` creates
 * its own `useQuery` subscription to the timezone preference. With 50+ TaskCards
 * visible, that means 50+ independent subscriptions to the same query key.
 * This provider lifts the subscription to a single point and distributes the
 * (memoized) result via React context.
 */
export function DayContextProvider({ children }: { children: ReactNode }) {
  const { timezone } = useConfiguredTimezone();

  // Explicit midnight-rollover trigger. The previous
  // "key on ymdFromDateParts(new Date(), timezone)" trick only flipped
  // on the NEXT render — an app open across midnight with no external
  // render trigger (no MCP push, no focus change, no mutation) kept
  // yesterday's `todayYmd` forever. Drive the rollover from a one-shot
  // setTimeout that re-arms at each local midnight.
  const [, forceMidnightRerender] = useState(0);
  useEffect(() => {
    return startDayContextRolloverRuntime(createBrowserDayContextRolloverRuntimeDeps({
      getCurrentYmd: () => ymdFromDateParts(new Date(), timezone),
      getDelayMs: () => msUntilNextMidnightInTimezone(timezone),
      onRollover: () => forceMidnightRerender((t) => t + 1),
    }));
  }, [timezone]);

  // Memoize so consumers get a referentially-stable object unless the
  // timezone or today's YMD actually changes.
  const todayYmd = ymdFromDateParts(new Date(), timezone);
  const dayContext = useMemo(() => {
    return {
      timezone,
      todayYmd,
      tomorrowYmd: addYmdDays(todayYmd, 1),
    };
  }, [timezone, todayYmd]);

  return (
    <DayContextContext.Provider value={dayContext}>
      {children}
    </DayContextContext.Provider>
  );
}

/**
 * Read the shared DayContext from the nearest `<DayContextProvider>`.
 *
 * For components that render outside the provider tree (e.g. overlay windows
 * that don't go through the main app shell), use `useConfiguredDayContext()`
 * from `./dayContext` instead — it creates its own query subscription.
 */
export function useDayContext(): DayContext {
  const ctx = useContext(DayContextContext);
  if (!ctx) {
    throw new Error('useDayContext must be used within a <DayContextProvider>');
  }
  return ctx;
}
