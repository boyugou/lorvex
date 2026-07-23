/**
 * Partition the controller's `futureDates` array into the Today /
 * Week / Later semantic groups the `Sections/{Today,Week,Later}.tsx`
 * components each render.
 *
 *   - Today: the entry where the ymd equals `todayYmd` (zero or one)
 *   - Week: the next 6 ymds after today (whichever of them exist in
 *     `futureDates`)
 *   - Later: every remaining ymd beyond the 7-day horizon
 *
 * Operating on the orchestrator's already-filtered `futureDates` keeps
 * the grouping a pure projection — no extra Date math, just slice
 * boundaries.
 */
export interface FutureDateGroups {
  today: string[];
  week: string[];
  later: string[];
}

export function groupFutureDates(futureDates: readonly string[], todayYmd: string): FutureDateGroups {
  const today: string[] = [];
  const week: string[] = [];
  const later: string[] = [];
  for (const date of futureDates) {
    if (date === todayYmd) {
      today.push(date);
      continue;
    }
    if (isWithinNextSixDays(date, todayYmd)) {
      week.push(date);
    } else {
      later.push(date);
    }
  }
  return { today, week, later };
}

function isWithinNextSixDays(date: string, todayYmd: string): boolean {
  const target = Date.parse(`${date}T00:00:00Z`);
  const anchor = Date.parse(`${todayYmd}T00:00:00Z`);
  if (Number.isNaN(target) || Number.isNaN(anchor)) return false;
  const dayMs = 86_400_000;
  const diffDays = Math.round((target - anchor) / dayMs);
  return diffDays > 0 && diffDays <= 6;
}
