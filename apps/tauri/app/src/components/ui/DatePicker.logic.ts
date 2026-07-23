import { formatCalendarDate } from '@/lib/dates/dateLocale';
import { daysInYmdMonth, parseYmd, ymdFromParts } from '@/lib/dayContextMath';

const DEFAULT_DATE_PICKER_FOCUS_YMD = '2026-01-01';
const DATE_PICKER_WEEKDAY_KEYS = [
  'calendar.weekday.su',
  'calendar.weekday.mo',
  'calendar.weekday.tu',
  'calendar.weekday.we',
  'calendar.weekday.th',
  'calendar.weekday.fr',
  'calendar.weekday.sa',
] as const;

export type DatePickerCell = { day: number; ymd: string } | null;
export type DatePickerWeekdayKey = typeof DATE_PICKER_WEEKDAY_KEYS[number];

function normalizeWeekStartDayIndex(startDay: number): number {
  return Number.isInteger(startDay) && startDay >= 0 && startDay <= 6 ? startDay : 0;
}

export function getDatePickerWeekdayKeys(startDay: number): DatePickerWeekdayKey[] {
  const normalizedStartDay = normalizeWeekStartDayIndex(startDay);
  return [
    ...DATE_PICKER_WEEKDAY_KEYS.slice(normalizedStartDay),
    ...DATE_PICKER_WEEKDAY_KEYS.slice(0, normalizedStartDay),
  ];
}

export function buildDatePickerGrid(year: number, month: number, weekStartDay: number): DatePickerCell[] {
  const totalDays = daysInYmdMonth(year, month);
  const normalizedWeekStart = normalizeWeekStartDayIndex(weekStartDay);
  const firstDow = (new Date(year, month, 1).getDay() - normalizedWeekStart + 7) % 7;
  const cells: DatePickerCell[] = [];
  for (let i = 0; i < firstDow; i++) cells.push(null);
  for (let day = 1; day <= totalDays; day++) {
    cells.push({ day, ymd: ymdFromParts(year, month, day) });
  }
  while (cells.length % 7 !== 0) cells.push(null);
  return cells;
}

export function formatDatePickerDayAriaLabel({
  ymd,
  locale,
  isToday,
  todayLabel,
}: {
  ymd: string;
  locale: string;
  isToday: boolean;
  todayLabel: string;
}): string {
  const fullDate = parseYmd(ymd)
    ? formatCalendarDate(ymd, locale, {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    })
    : ymd;
  return isToday ? `${fullDate} (${todayLabel})` : fullDate;
}

export function resolveDatePickerInitialFocusYmd({
  value,
  todayYmd,
  minDate,
}: {
  value: string | null;
  todayYmd: string;
  minDate?: string | undefined;
}): string {
  const normalizedMinDate = minDate && parseYmd(minDate) ? minDate : null;
  const candidates = [
    value,
    todayYmd,
    normalizedMinDate,
    DEFAULT_DATE_PICKER_FOCUS_YMD,
  ];

  for (const candidate of candidates) {
    if (!candidate || !parseYmd(candidate)) continue;
    if (normalizedMinDate && candidate < normalizedMinDate) continue;
    return candidate;
  }

  return normalizedMinDate ?? DEFAULT_DATE_PICKER_FOCUS_YMD;
}

export function resolveDatePickerMonthFocusYmd({
  year,
  month,
  focusedYmd,
  minDate,
}: {
  year: number;
  month: number;
  focusedYmd: string;
  minDate?: string | undefined;
}): string {
  const normalizedMinDate = minDate && parseYmd(minDate) ? minDate : null;
  const focused = parseYmd(focusedYmd);
  const lastDay = daysInYmdMonth(year, month);
  const preferredDay = Math.min(focused?.day ?? 1, lastDay);

  for (let day = preferredDay; day <= lastDay; day += 1) {
    const candidate = ymdFromParts(year, month, day);
    if (!normalizedMinDate || candidate >= normalizedMinDate) return candidate;
  }
  for (let day = preferredDay - 1; day >= 1; day -= 1) {
    const candidate = ymdFromParts(year, month, day);
    if (!normalizedMinDate || candidate >= normalizedMinDate) return candidate;
  }

  return resolveDatePickerInitialFocusYmd({
    value: null,
    todayYmd: ymdFromParts(year, month, 1),
    minDate,
  });
}

/**
 * WAI-ARIA grid keyboard nav delta keys recognized by the DatePicker
 * controller. Arrow keys step by day/week; PageUp/PageDown step by
 * month (with Shift for year); Home/End jump to the start/end of the
 * focused week according to `weekStartDay`.
 */
export function resolveDatePickerArrowFocusYmd({
  focusedYmd,
  key,
  shiftKey,
  weekStartDay = 0,
  isDisabled,
  minDate,
  maxSteps = 366,
}: {
  focusedYmd: string;
  key: string;
  shiftKey?: boolean;
  weekStartDay?: number;
  isDisabled?: ((ymd: string) => boolean) | undefined;
  minDate?: string | undefined;
  maxSteps?: number;
}): string {
  const parsed = parseYmd(focusedYmd);
  if (!parsed) return focusedYmd;

  const normalizedMinDate = minDate && parseYmd(minDate) ? minDate : null;
  const rejectsCandidate = isDisabled ?? ((ymd: string) => normalizedMinDate ? ymd < normalizedMinDate : false);
  const normalizedWeekStart = Number.isInteger(weekStartDay) && weekStartDay >= 0 && weekStartDay <= 6 ? weekStartDay : 0;

  // Home/End jump to the start/end of the focused week using the
  // active week-start preference so the keyboard contract lines up
  // with the visual grid header.
  if (key === 'Home' || key === 'End') {
    const dow = new Date(parsed.year, parsed.month, parsed.day).getDay();
    const offsetFromStart = (dow - normalizedWeekStart + 7) % 7;
    const stepDays = key === 'Home' ? -offsetFromStart : 6 - offsetFromStart;
    return stepInDirection(parsed, stepDays, rejectsCandidate);
  }

  // PageUp/PageDown — same day-of-month one month away; Shift jumps a
  // year. Falls back to the closest in-range day if the target month
  // is shorter (e.g. PageDown from Jan 31 lands on Feb 28/29).
  if (key === 'PageUp' || key === 'PageDown') {
    const dir = key === 'PageUp' ? -1 : 1;
    const stepMonths = shiftKey ? 12 * dir : dir;
    return jumpMonths(parsed, stepMonths, rejectsCandidate, normalizedMinDate);
  }

  let deltaDays = 0;
  if (key === 'ArrowLeft') deltaDays = -1;
  else if (key === 'ArrowRight') deltaDays = 1;
  else if (key === 'ArrowUp') deltaDays = -7;
  else if (key === 'ArrowDown') deltaDays = 7;
  else return focusedYmd;

  let stepDay = parsed.day;
  let stepMonth = parsed.month;
  let stepYear = parsed.year;
  for (let step = 1; step <= maxSteps; step += 1) {
    const date = new Date(stepYear, stepMonth, stepDay + deltaDays);
    stepDay = date.getDate();
    stepMonth = date.getMonth();
    stepYear = date.getFullYear();
    const candidateYmd = ymdFromParts(stepYear, stepMonth, stepDay);
    if (!rejectsCandidate(candidateYmd)) return candidateYmd;
  }

  return focusedYmd;
}

function stepInDirection(
  start: { year: number; month: number; day: number },
  deltaDays: number,
  rejectsCandidate: (ymd: string) => boolean,
): string {
  const date = new Date(start.year, start.month, start.day + deltaDays);
  const ymd = ymdFromParts(date.getFullYear(), date.getMonth(), date.getDate());
  if (!rejectsCandidate(ymd)) return ymd;
  // If the direct candidate is rejected (e.g. before minDate), walk
  // back toward `start` one day at a time so the focus lands on the
  // closest in-range cell. This keeps Home/End usable even when the
  // viewport's leading edge clips into a disabled range.
  const sign = deltaDays >= 0 ? -1 : 1;
  for (let walk = Math.abs(deltaDays) - 1; walk > 0; walk -= 1) {
    const candidate = new Date(start.year, start.month, start.day + deltaDays + sign * (Math.abs(deltaDays) - walk));
    const candidateYmd = ymdFromParts(candidate.getFullYear(), candidate.getMonth(), candidate.getDate());
    if (!rejectsCandidate(candidateYmd)) return candidateYmd;
  }
  return ymdFromParts(start.year, start.month, start.day);
}

function jumpMonths(
  start: { year: number; month: number; day: number },
  stepMonths: number,
  rejectsCandidate: (ymd: string) => boolean,
  normalizedMinDate: string | null,
): string {
  const targetMonthIndex = start.month + stepMonths;
  const targetYear = start.year + Math.floor(targetMonthIndex / 12);
  const targetMonth = ((targetMonthIndex % 12) + 12) % 12;
  const lastDay = daysInYmdMonth(targetYear, targetMonth);
  const preferredDay = Math.min(start.day, lastDay);
  for (let day = preferredDay; day >= 1; day -= 1) {
    const ymd = ymdFromParts(targetYear, targetMonth, day);
    if (!rejectsCandidate(ymd)) return ymd;
  }
  // Fall back to walking forward into the next month if everything in
  // the target month is rejected (only possible when minDate clips the
  // entire month). `resolveDatePickerInitialFocusYmd` settles on the
  // earliest valid day at or beyond minDate.
  return resolveDatePickerInitialFocusYmd({
    value: null,
    todayYmd: ymdFromParts(targetYear, targetMonth, 1),
    ...(normalizedMinDate ? { minDate: normalizedMinDate } : {}),
  });
}
