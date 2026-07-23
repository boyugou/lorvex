import type { TranslationKey } from '@/lib/i18n';
import {
  addYmdDays,
  daysInYmdMonth,
  isCanonicalYmd,
  parseYmd,
  ymdFromParts,
} from '@/lib/dayContextMath';
import { tryParseJson } from '@/lib/security/jsonParse';
import {
  parseTaskRecurrence,
  type TaskRecurrenceWeekdayCode,
} from '@/lib/taskRecurrence';
import { hasOnlyKeys, isPlainRecord as isRecord } from '@/lib/objectGuards';

export const CALENDAR_TASK_DRAG_MIME = 'application/x-calendar-task';

/** Prefix used on recurring events/tasks in calendar grids. */
export const RECURRENCE_SYMBOL = '↻ ';

/**
 * Encoded drag payload for calendar task rescheduling.
 *
 * `oldTime` is the task's existing `due_time` (wire "HH:MM" or `null` when
 * untimed). It lets the week timeline's Y→time drop decide whether anything
 * actually changed before issuing a reschedule; the day-only surfaces
 * (MonthGrid cells) ignore it.
 */
interface CalendarTaskDragPayload {
  id: string;
  oldDate: string | null;
  oldTime: string | null;
  hasPlannedDate: boolean;
}

const CALENDAR_TASK_DRAG_PAYLOAD_KEYS = new Set(['hasPlannedDate', 'id', 'oldDate', 'oldTime']);

function hasOnlyCalendarTaskDragPayloadKeys(value: Record<string, unknown>): boolean {
  return hasOnlyKeys(value, CALENDAR_TASK_DRAG_PAYLOAD_KEYS);
}

const WIRE_TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;

export function encodeCalendarTaskDrag(
  taskId: string,
  oldDate: string | null,
  hasPlannedDate = false,
  oldTime: string | null = null,
): string {
  return JSON.stringify({ id: taskId, oldDate, oldTime, hasPlannedDate });
}

export function decodeCalendarTaskDrag(raw: string): CalendarTaskDragPayload | null {
  const parsed = tryParseJson(raw);
  if (!parsed.ok) {
    return null;
  }
  if (!isRecord(parsed.value) || !hasOnlyCalendarTaskDragPayloadKeys(parsed.value)) {
    return null;
  }
  const payload = parsed.value;
  if (typeof payload.id !== 'string' || payload.id.trim() === '' || payload.id !== payload.id.trim()) {
    return null;
  }
  if (payload.oldDate !== null && !isCanonicalYmd(payload.oldDate)) return null;
  if (typeof payload.hasPlannedDate !== 'boolean') return null;
  // `oldTime` is optional on the wire: older/leaner encoders may omit it.
  // Treat a missing key as untimed (`null`); reject a present-but-malformed value.
  let oldTime: string | null = null;
  if ('oldTime' in payload) {
    if (payload.oldTime !== null) {
      if (typeof payload.oldTime !== 'string' || !WIRE_TIME_PATTERN.test(payload.oldTime)) {
        return null;
      }
      oldTime = payload.oldTime;
    }
  }
  return {
    id: payload.id,
    oldDate: payload.oldDate,
    oldTime,
    hasPlannedDate: payload.hasPlannedDate,
  };
}

export function toDateStr(y: number, m: number, d: number): string {
  return ymdFromParts(y, m, d);
}

export function daysInMonth(year: number, month: number): number {
  return daysInYmdMonth(year, month);
}

/** Returns the offset of the 1st of the month relative to the grid's week start day. */
export function firstDayOfWeek(year: number, month: number, weekStartDay = 0): number {
  const dow = new Date(year, month, 1).getDay();
  return (dow - weekStartDay + 7) % 7;
}

export function addDays(dateStr: string, n: number): string {
  return addYmdDays(dateStr, n);
}

/** Returns the day that starts the week containing dateStr (anchored to weekStartDay: 0=Sun, 1=Mon). */
export function weekAnchor(dateStr: string, weekStartDay = 0): string {
  const parsed = parseYmd(dateStr);
  if (!parsed) return dateStr;
  const d = new Date(Date.UTC(parsed.year, parsed.month, parsed.day));
  const offset = (d.getUTCDay() - weekStartDay + 7) % 7;
  return addYmdDays(dateStr, -offset);
}

export function resolveWeekStartAnchor(
  activeDate: string | null,
  todayYmd: string,
  weekStartDay = 0,
): string {
  return weekAnchor(activeDate ?? todayYmd, weekStartDay);
}

export function formatTimeRange(
  ev: { all_day: boolean; start_time: string | null; end_time: string | null },
  allDayLabel: string,
): string {
  if (ev.all_day) return allDayLabel;
  const parts: string[] = [];
  if (ev.start_time) parts.push(ev.start_time);
  if (ev.end_time) parts.push(ev.end_time);
  return parts.join(' – ');
}

export type CalendarRecurrencePreset = 'none' | 'daily' | 'weekly' | 'monthly' | 'yearly' | 'advanced';
export type CalendarRecurrenceEndCondition = 'never' | 'onDate';
export type WeekdayCode = TaskRecurrenceWeekdayCode;

export const WEEKDAY_ORDER: WeekdayCode[] = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];

export const WEEKDAY_OPTIONS: Array<{ code: WeekdayCode; labelKey: TranslationKey }> = [
  { code: 'SU', labelKey: 'calendar.weekday.su' },
  { code: 'MO', labelKey: 'calendar.weekday.mo' },
  { code: 'TU', labelKey: 'calendar.weekday.tu' },
  { code: 'WE', labelKey: 'calendar.weekday.we' },
  { code: 'TH', labelKey: 'calendar.weekday.th' },
  { code: 'FR', labelKey: 'calendar.weekday.fr' },
  { code: 'SA', labelKey: 'calendar.weekday.sa' },
];

export function weekdayCodeFromDate(dateStr: string): WeekdayCode {
  const parsed = parseYmd(dateStr);
  if (!parsed) return 'SU';
  const date = new Date(Date.UTC(parsed.year, parsed.month, parsed.day));
  return WEEKDAY_ORDER[date.getUTCDay()] ?? 'SU';
}

export function recurrenceFromRaw(raw: string | null, startDate: string): {
  preset: CalendarRecurrencePreset;
  interval: number;
  byday: WeekdayCode[];
  endCondition: CalendarRecurrenceEndCondition;
  until: string;
} {
  const fallbackDay = weekdayCodeFromDate(startDate);
  const fallback = {
    preset: 'none' as const,
    interval: 1,
    byday: [fallbackDay],
    endCondition: 'never' as const,
    until: '',
  };
  if (!raw) {
    return fallback;
  }
  const recurrence = parseTaskRecurrence(raw);
  if (!recurrence) {
    return fallback;
  }
  const freqToPreset: Record<string, CalendarRecurrencePreset> = {
    DAILY: 'daily',
    WEEKLY: 'weekly',
    MONTHLY: 'monthly',
    YEARLY: 'yearly',
  };
  const preset = freqToPreset[recurrence.freq];
  if (preset) {
    return {
      preset: recurrence.editable ? preset : 'advanced',
      interval: recurrence.interval ?? 1,
      byday: preset === 'weekly' && recurrence.editable
        ? (recurrence.byday && recurrence.byday.length > 0 ? recurrence.byday : [fallbackDay])
        : [],
      endCondition: recurrence.until ? 'onDate' : 'never',
      until: recurrence.until ?? '',
    };
  }
  return fallback;
}

export function recurrencePresetToRaw(
  preset: CalendarRecurrencePreset,
  interval: number,
  byday: WeekdayCode[],
  endCondition: CalendarRecurrenceEndCondition,
  untilDate: string,
  fallbackStartDate: string,
): string | null {
  if (preset === 'none') return null;
  if (preset === 'advanced') return null;
  const presetToFreq: Record<string, string> = {
    daily: 'DAILY',
    weekly: 'WEEKLY',
    monthly: 'MONTHLY',
    yearly: 'YEARLY',
  };
  const payload: Record<string, unknown> = {
    FREQ: presetToFreq[preset] ?? preset.toUpperCase(),
    INTERVAL: Math.max(1, Math.floor(interval || 1)),
  };
  if (preset === 'weekly') {
    const fallbackDay = weekdayCodeFromDate(fallbackStartDate);
    const selected = byday.length > 0 ? byday : [fallbackDay];
    payload.BYDAY = WEEKDAY_ORDER.filter((code) => selected.includes(code));
  }
  if (endCondition === 'onDate' && untilDate) {
    payload.UNTIL = untilDate;
  }
  return JSON.stringify(payload);
}
