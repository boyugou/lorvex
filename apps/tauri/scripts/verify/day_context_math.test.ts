// Regression pins for the pure calendar/timezone math extracted from
// `app/src/lib/dayContext.ts`. Exercised by
// `scripts/verify/day_context_math.mjs`. Run directly with
// `node --experimental-strip-types` — see the runner for the exact
// invocation..

import {
  addYmdDays,
  getNextMondayYmd,
  getNextWeekendYmd,
  isoFromDatetimeLocalInTimezone,
  ymdFromDateParts,
} from '../../app/src/lib/dayContextMath.ts';

let failures = 0;

function assertEq<T>(label: string, actual: T, expected: T): void {
  const pass =
    typeof actual === 'object'
      ? JSON.stringify(actual) === JSON.stringify(expected)
      : actual === expected;
  if (!pass) {
    failures += 1;
    console.error(`  ✗ ${label}\n      expected: ${String(expected)}\n      actual:   ${String(actual)}`);
  } else {
    console.log(`  ✓ ${label}`);
  }
}

function section(name: string, fn: () => void): void {
  console.log(`\n${name}`);
  fn();
}

// ── addYmdDays ──────────────────────────────────────────────────
section('addYmdDays', () => {
  assertEq('month boundary forward', addYmdDays('2026-01-31', 1), '2026-02-01');
  assertEq('month boundary backward', addYmdDays('2026-02-01', -1), '2026-01-31');
  assertEq('leap day (2024)', addYmdDays('2024-02-28', 1), '2024-02-29');
  assertEq('non-leap Feb→Mar (2023)', addYmdDays('2023-02-28', 1), '2023-03-01');
  assertEq('year boundary', addYmdDays('2026-12-31', 1), '2027-01-01');
  assertEq('zero offset is identity', addYmdDays('2026-04-18', 0), '2026-04-18');
  assertEq('large offset (30 days)', addYmdDays('2026-01-01', 30), '2026-01-31');
  assertEq('negative offset (-7)', addYmdDays('2026-03-08', -7), '2026-03-01');
});

// DST-stability: in America/New_York, DST started Sunday 2026-03-08.
// The `+1 day from 2026-03-07` result must still be 2026-03-08 even
// though that day is only 23h long in wall-clock terms — the UTC
// anchor defends against the classic `setDate` off-by-one.
section('addYmdDays DST-safety', () => {
  assertEq('US DST spring-forward step', addYmdDays('2026-03-07', 1), '2026-03-08');
  assertEq('US DST spring-forward cross', addYmdDays('2026-03-08', 1), '2026-03-09');
  assertEq('EU DST spring-forward step', addYmdDays('2026-03-28', 1), '2026-03-29');
  assertEq('EU DST fall-back step', addYmdDays('2026-10-24', 1), '2026-10-25');
});

// ── ymdFromDateParts ──────────────────────────────────────────────
// Build explicit UTC instants so the tests don't depend on the host
// clock, then check what timezone-local date each instant falls on.
section('ymdFromDateParts', () => {
  // 2026-04-18T22:00:00Z is still April 18 in UTC but April 19 in
  // Asia/Tokyo (+09) and April 18 in America/Los_Angeles (-07).
  const instant = new Date('2026-04-18T22:00:00Z');
  assertEq('UTC', ymdFromDateParts(instant, 'UTC'), '2026-04-18');
  assertEq('Asia/Tokyo rolls forward', ymdFromDateParts(instant, 'Asia/Tokyo'), '2026-04-19');
  assertEq('America/Los_Angeles stays same', ymdFromDateParts(instant, 'America/Los_Angeles'), '2026-04-18');
});

// ── getNextWeekendYmd (#2498 invariant) ───────────────────────────
// Pick noon UTC on known weekdays in UTC timezone so the math is
// stable regardless of host tz.
section('getNextWeekendYmd (#2498)', () => {
  // 2026-04-13 is a Monday (weekday=1). Next Saturday is 2026-04-18.
  assertEq(
    'Monday → next Saturday',
    getNextWeekendYmd('UTC', new Date('2026-04-13T12:00:00Z')),
    '2026-04-18',
  );
  // 2026-04-17 is a Friday (weekday=5). Next Saturday is 2026-04-18.
  assertEq(
    'Friday → tomorrow Saturday',
    getNextWeekendYmd('UTC', new Date('2026-04-17T12:00:00Z')),
    '2026-04-18',
  );
  // 2026-04-18 is a Saturday. #2498: must return today, NOT next weekend.
  assertEq(
    'Saturday → today (#2498 invariant)',
    getNextWeekendYmd('UTC', new Date('2026-04-18T12:00:00Z')),
    '2026-04-18',
  );
  // 2026-04-19 is a Sunday. #2498: must return today, NOT next weekend.
  assertEq(
    'Sunday → today (#2498 invariant)',
    getNextWeekendYmd('UTC', new Date('2026-04-19T12:00:00Z')),
    '2026-04-19',
  );
});

// ── getNextMondayYmd (DST#1 invariant) ────────────────────────────
section('getNextMondayYmd (DST#1)', () => {
  // 2026-04-13 is Monday. DST#1: must return today, NOT next Monday.
  assertEq(
    'Monday → today (DST#1 invariant)',
    getNextMondayYmd('UTC', new Date('2026-04-13T12:00:00Z')),
    '2026-04-13',
  );
  // 2026-04-14 is Tuesday. Next Monday is 2026-04-20.
  assertEq(
    'Tuesday → next Monday',
    getNextMondayYmd('UTC', new Date('2026-04-14T12:00:00Z')),
    '2026-04-20',
  );
  // 2026-04-19 is Sunday. Next Monday is 2026-04-20 (1 day away).
  assertEq(
    'Sunday → next Monday',
    getNextMondayYmd('UTC', new Date('2026-04-19T12:00:00Z')),
    '2026-04-20',
  );
});

// ── isoFromDatetimeLocalInTimezone (#3051 M8) ─────────────────────
// Pin DST edge cases AND a non-hour-boundary zone so a refactor that
// breaks the offset-probe semantics surfaces here. The function
// converts wall-clock input in `timeZone` to a UTC ISO timestamp.
section('isoFromDatetimeLocalInTimezone (#3051 M8)', () => {
  // Normal (non-DST) day in America/New_York: 2026-04-15 14:30 EDT.
  // EDT = UTC-04:00, so 14:30 local → 18:30 UTC.
  assertEq(
    'normal day America/New_York',
    isoFromDatetimeLocalInTimezone('2026-04-15T14:30', 'America/New_York'),
    '2026-04-15T18:30:00.000Z',
  );

  // +05:30 zone (Asia/Kolkata is fixed; no DST). 09:00 IST → 03:30 UTC.
  // Pins half-hour-offset zone handling — a regression that rounded
  // the offset to whole hours would surface here.
  assertEq(
    'half-hour-offset zone Asia/Kolkata',
    isoFromDatetimeLocalInTimezone('2026-04-15T09:00', 'Asia/Kolkata'),
    '2026-04-15T03:30:00.000Z',
  );

  // Spring forward gap: America/New_York 2026-03-08 02:30 does NOT
  // exist on the clock (clocks jumped 02:00 → 03:00 EDT). Doc-comment
  // pins the SUMMER (DST, -04:00) interpretation: 02:30 → 06:30 UTC.
  assertEq(
    'spring-forward gap → summer interpretation',
    isoFromDatetimeLocalInTimezone('2026-03-08T02:30', 'America/New_York'),
    '2026-03-08T06:30:00.000Z',
  );

  // Fall back ambiguous hour: America/New_York 2026-11-01 01:30 occurs
  // twice (once at -04:00 EDT before the fallback, once at -05:00 EST
  // after). Doc-comment pins the FIRST occurrence (pre-transition,
  // DST -04:00): 01:30 → 05:30 UTC. Property of the offset-probe
  // algorithm — the first guess lands in DST and converges there.
  assertEq(
    'fall-back ambiguous → DST (first-occurrence) interpretation',
    isoFromDatetimeLocalInTimezone('2026-11-01T01:30', 'America/New_York'),
    '2026-11-01T05:30:00.000Z',
  );

  // Unparseable input → null. Pins the "wrong shape" exit so a
  // future refactor doesn't silently swallow malformed values.
  assertEq(
    'unparseable input returns null',
    isoFromDatetimeLocalInTimezone('not-a-datetime', 'UTC'),
    null,
  );
});

console.log('');
if (failures > 0) {
  console.error(`[verify:day-context-math] ${failures} assertion(s) failed.`);
  process.exit(1);
}
console.log('[verify:day-context-math] OK');
