import { useEffect, useState } from 'react';
import { useRuntimeProfile } from '@/lib/useRuntimeProfile';

import {
  MOBILE_BREAKPOINT_PX,
  installMonthGridMediaRuntime,
  readMonthGridNarrowMatch,
} from '../monthGrid.runtime';

import { DesktopMonthGrid } from './DesktopMonthGrid';
import { MobileWeekGrid } from './MobileWeekGrid';
import type { MonthGridProps } from './types';

export type { MonthGridProps } from './types';

/**
 * MonthGrid entry point.
 *
 * Chooses between the dense desktop month grid and the tap-first mobile
 * week grid. The runtimeClass from `useRuntimeProfile` is the
 * authoritative desktop/mobile signal (see `app/src/lib/platform.ts`); a
 * CSS media query is the secondary signal so small desktop windows
 * (e.g. docked side panels) also get the readable, tap-first layout.
 *
 * The two branches were split out into sibling modules during the
 * M29 refactor — the original single-file MonthGrid.tsx grew to
 * 780 LOC mixing desktop layout math, mobile week navigation, and two
 * pill subcomponents. The split keeps each module under ~250 LOC and
 * isolates the desktop ResizeObserver math behind `useDesktopMonthLayout`.
 */
export function MonthGrid(props: MonthGridProps) {
  const runtimeProfile = useRuntimeProfile();
  const isMobileRuntime = runtimeProfile.runtimeClass === 'mobile';
  const [isNarrow, setIsNarrow] = useState<boolean>(() => {
    if (typeof window === 'undefined') return false;
    return readMonthGridNarrowMatch(
      () => window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT_PX}px)`),
    );
  });
  useEffect(() => {
    if (typeof window === 'undefined') return;
    return installMonthGridMediaRuntime({
      createMediaQueryList: () => window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT_PX}px)`),
      onMatchesChange: setIsNarrow,
    });
  }, []);
  const useMobileLayout = isMobileRuntime || isNarrow;

  if (useMobileLayout) {
    return <MobileWeekGrid {...props} />;
  }
  return <DesktopMonthGrid {...props} />;
}
