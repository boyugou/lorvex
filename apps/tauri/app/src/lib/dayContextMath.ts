// Pure calendar / timezone math extracted from `dayContext.ts` so the
// logic is testable without the React + TanStack Query + Tauri IPC
// imports that the hook-layer module carries.
//
// Every function here is a pure function of its inputs; no side
// effects, no mutable state, no module-level globals. That lets the
// Node-based verifier (`scripts/verify/day_context_math.mjs`) import
// this file directly via `--experimental-strip-types` and exercise
// the regression boundaries (DST, leap years, month wrap,
// weekend-today, DST#1 Monday-today) without the full app toolchain.

import { isoFromWallTimeInTimezone } from './dates/timezoneMath.ts';

export interface ParsedYmd {
  year: number;
  /** Zero-based month index, matching JavaScript Date APIs. */
  month: number;
  day: number;
}

const CANONICAL_YMD_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const MS_PER_DAY = 86_400_000;

export function daysInYmdMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
}

export function ymdFromParts(year: number, month: number, day: number): string {
  return `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

export function parseYmd(value: unknown): ParsedYmd | null {
  if (typeof value !== 'string') return null;
  const match = CANONICAL_YMD_PATTERN.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const monthOneBased = Number(match[2]);
  const day = Number(match[3]);
  if (!Number.isInteger(year) || year < 1 || year > 9999) return null;
  if (!Number.isInteger(monthOneBased) || monthOneBased < 1 || monthOneBased > 12) return null;
  const month = monthOneBased - 1;
  if (!Number.isInteger(day) || day < 1 || day > daysInYmdMonth(year, month)) return null;
  return { year, month, day };
}

export function isCanonicalYmd(value: unknown): value is string {
  return parseYmd(value) !== null;
}

/**
 * Return the `YYYY-MM-DD` string for `date` as seen in `timeZone`.
 * Uses `Intl.DateTimeFormat('en-CA')` because its canonical output
 * format is already `YYYY-MM-DD`, so we avoid locale-sensitive
 * reassembly.
 */
export function ymdFromDateParts(date: Date, timeZone: string): string {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const parts = formatter.formatToParts(date);
  const year = parts.find((part) => part.type === 'year')?.value ?? '1970';
  const month = parts.find((part) => part.type === 'month')?.value ?? '01';
  const day = parts.find((part) => part.type === 'day')?.value ?? '01';
  return `${year}-${month}-${day}`;
}

/**
 * Offset a `YYYY-MM-DD` string by `offsetDays` via UTC arithmetic.
 *
 * The YMD identifies a local calendar day, but we use UTC for the
 * arithmetic because JS local-time `Date.setDate` is DST-unsafe (a
 * +24h nudge on the day a timezone transitions can land on the same
 * wall-clock day at 23:00). Anchoring at UTC midnight and using
 * `setUTCDate` keeps the arithmetic purely on calendar indices.
 */
export function addYmdDays(dateYmd: string, offsetDays: number): string {
  const parsed = parseYmd(dateYmd);
  if (!parsed) return dateYmd;
  const value = new Date(Date.UTC(parsed.year, parsed.month, parsed.day));
  value.setUTCDate(value.getUTCDate() + offsetDays);
  return value.toISOString().slice(0, 10);
}

export function diffYmdDays(fromYmd: string, toYmd: string): number {
  const from = parseYmd(fromYmd);
  const to = parseYmd(toYmd);
  if (!from || !to) return 0;
  const fromMs = Date.UTC(from.year, from.month, from.day);
  const toMs = Date.UTC(to.year, to.month, to.day);
  return Math.round((toMs - fromMs) / MS_PER_DAY);
}

/**
 * Compute the number of milliseconds from `now` until the next local
 * midnight boundary in `timeZone`. Clamped to at least 1 000 ms so a
 * pathological state (clock exactly on midnight, slow render) can't
 * spin a zero-delay timer.
 */
export function msUntilNextMidnightInTimezone(
  timeZone: string,
  now: Date = new Date(),
): number {
  const startMs = now.getTime();
  const currentYmd = ymdFromDateParts(now, timeZone);
  let low = startMs;
  let high = startMs + 172_800_000;

  while (ymdFromDateParts(new Date(high), timeZone) === currentYmd) {
    high += 86_400_000;
  }

  while (high - low > 1_000) {
    const mid = Math.floor((low + high) / 2);
    if (ymdFromDateParts(new Date(mid), timeZone) === currentYmd) {
      low = mid;
    } else {
      high = mid;
    }
  }

  return Math.max(1_000, high - startMs);
}

function weekdayFromYmd(dateYmd: string): number {
  const parsed = parseYmd(dateYmd);
  if (!parsed) return 0;
  return new Date(Date.UTC(parsed.year, parsed.month, parsed.day)).getUTCDay();
}

export function getNextWeekendYmd(
  timeZone: string,
  now: Date = new Date(),
): string {
  const today = ymdFromDateParts(now, timeZone);
  const weekday = weekdayFromYmd(today);
  if (weekday === 6 || weekday === 0) {
    return today;
  }
  const daysUntilSaturday = (6 - weekday + 7) % 7;
  return addYmdDays(today, daysUntilSaturday);
}

/**
 * Convert a `<input type="datetime-local">` style string
 * (`YYYY-MM-DDTHH:mm` or `YYYY-MM-DDTHH:mm:ss`) into a UTC ISO timestamp,
 * interpreting the wall time in the supplied IANA timezone.
 *
 * The naive `new Date(value).toISOString()` approach treats the wall time as
 * being in the host browser timezone, which produces hours-off reminders for
 * travelers and dual-system users whose configured app timezone differs from
 * their machine timezone.
 *
 * Strategy: probe the timezone offset for the wall time using
 * `Intl.DateTimeFormat` parts. We compute the UTC instant whose wall-clock
 * representation in `timeZone` matches the input, by iterating once on the
 * offset (the offset of the first guess can be off by up to ±1 hour during
 * a DST transition near the input wall time, but converges in a single pass).
 *
 * ## DST edge-case behavior
 *
 * **Spring-forward gap (e.g. America/New_York 2025-03-09 02:30):** the wall
 * time does not exist on the clock that day. The two-pass probe converges
 * on the SUMMER (DST) interpretation — i.e. the input is treated as if the
 * clock had already advanced. This matches the convention used by every
 * major calendar UI (Apple Calendar, Google Calendar) and avoids
 * silently rejecting reminders the user typed during the gap.
 *
 * **Fall-back ambiguous hour (e.g. America/New_York 2025-11-02 01:30):**
 * the wall time occurs twice — once during DST (-04:00) and again after
 * the clock falls back (-05:00). The two-pass probe deterministically
 * converges on the FIRST occurrence (DST / pre-transition / -04:00).
 * This is a property of the offset-probe algorithm: the first guess
 * places the wall-clock instant in DST (because Date.UTC of the wall
 * time, treated as UTC, lands BEFORE the standard-time fallback), and
 * the second pass observes the same DST offset for the corrected
 * instant, so the iteration is stable on summer time. The choice is
 * deterministic for the same input but it IS a choice — callers that
 * need second-occurrence semantics should resolve the timestamp
 * explicitly via `Intl.DateTimeFormat` with the standard-time offset.
 *
 * Returns `null` if the value is unparseable.
 */
export function isoFromDatetimeLocalInTimezone(
  value: string,
  timeZone: string,
): string | null {
  return isoFromWallTimeInTimezone(value, timeZone);
}

export function getNextMondayYmd(
  timeZone: string,
  now: Date = new Date(),
): string {
  // when today IS Monday, the old `|| 7` coerced the
  // 0-day result to 7, silently pushing the task TWO Mondays out
  // instead of today. This is the exact twin of the weekend bug
  // fixed in — a user clicking "Next week" / "Next Monday"
  // on a Monday morning clearly means "today or this coming
  // Monday," not "the following Monday." Mirror the weekend
  // policy: Monday → today.
  const today = ymdFromDateParts(now, timeZone);
  const weekday = weekdayFromYmd(today);
  if (weekday === 1) {
    return today;
  }
  const daysUntilMonday = (1 - weekday + 7) % 7;
  return addYmdDays(today, daysUntilMonday);
}
