/**
 * Canonical millisecond duration constants.
 *
 * Use these for any time-window arithmetic (cache TTLs, stale thresholds,
 * setTimeout / setInterval intervals, "last N days" math) instead of
 * inline `60 * 60 * 1000` style expressions — the name documents the
 * unit, the arithmetic happens once, and a grep for `WEEK_MS` lands every
 * caller that talks in weeks.
 */
const SECOND_MS = 1000;
const MINUTE_MS = 60 * SECOND_MS;
export const HOUR_MS = 60 * MINUTE_MS;
export const DAY_MS = 24 * HOUR_MS;
export const WEEK_MS = 7 * DAY_MS;
