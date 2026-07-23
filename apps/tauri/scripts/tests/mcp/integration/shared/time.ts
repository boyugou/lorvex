/**
 * Calendar-day helpers for MCP integration tests.
 *
 * the harness previously mixed `new Date().toISOString().slice(0, 10)`
 * (UTC day) with `getFullYear/getMonth/getDate` (local-system day) across
 * different test files, so two tests running in the same harness could
 * disagree on "today" whenever the CI runner ran near midnight. The
 * MCP server interprets dates in the user's `PREF_TIMEZONE`, so the
 * canonical contract is: **all integration tests anchor on UTC**, and
 * the harness runner pins `TZ=UTC` for the MCP server it spawns. One
 * helper below; never compute dates inline in a test file.
 */

function utcDayYmd(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** Today in UTC as `YYYY-MM-DD`, offset by `offsetDays`. Replaces legacy
 *  local-time helpers and inline `toISOString().slice` idioms. */
export function daysFromTodayYmd(offsetDays = 0): string {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + offsetDays);
  return utcDayYmd(date);
}

export function isoDaysAgo(days: number): string {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString();
}
