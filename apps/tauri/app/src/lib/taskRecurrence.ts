import { isCanonicalYmd } from './dayContextMath';
import { RECURRENCE_INTERVAL_MAX } from './recurrenceInterval';
import { tryParseJson } from './security/jsonParse';
import { hasOnlyKeys, isPlainRecord as isRecord } from './objectGuards';

export type TaskRecurrenceFrequency = 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';
export type TaskRecurrenceWeekdayCode = 'SU' | 'MO' | 'TU' | 'WE' | 'TH' | 'FR' | 'SA';

export interface ParsedTaskRecurrence {
  freq: TaskRecurrenceFrequency;
  editable: boolean;
  interval?: number | undefined;
  byday?: TaskRecurrenceWeekdayCode[] | undefined;
  until?: string | undefined;
}

export type TaskRecurrenceRulePatch =
  | {
      FREQ: TaskRecurrenceFrequency;
      INTERVAL?: number;
      BYDAY?: TaskRecurrenceWeekdayCode[];
      UNTIL?: string;
    }
  | null;

const TASK_RECURRENCE_KEYS = new Set([
  'BYDAY',
  'BYMONTH',
  'BYMONTHDAY',
  'BYSETPOS',
  'COUNT',
  'FREQ',
  'INTERVAL',
  'UNTIL',
  'WKST',
]);
const SIMPLE_TASK_RECURRENCE_KEYS = new Set(['BYDAY', 'FREQ', 'INTERVAL', 'UNTIL']);
const TASK_RECURRENCE_FREQS = new Set(['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY']);
const WEEKDAY_CODES = new Set(['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA']);
const BYDAY_TOKEN = /^[+-]?(?:[1-9]|[1-4][0-9]|5[0-3])?(?:SU|MO|TU|WE|TH|FR|SA)$/;
function isTaskRecurrenceFrequency(value: unknown): value is TaskRecurrenceFrequency {
  return typeof value === 'string' && TASK_RECURRENCE_FREQS.has(value);
}

function isTaskRecurrenceWeekdayCode(value: unknown): value is TaskRecurrenceWeekdayCode {
  return typeof value === 'string' && WEEKDAY_CODES.has(value);
}

function isBydayToken(value: unknown): value is string {
  return typeof value === 'string' && BYDAY_TOKEN.test(value);
}

export function parseTaskRecurrence(raw: string | null | undefined): ParsedTaskRecurrence | null {
  if (!raw) return null;
  const parsed = tryParseJson(raw);
  if (!parsed.ok || !isRecord(parsed.value) || !hasOnlyKeys(parsed.value, TASK_RECURRENCE_KEYS)) {
    return null;
  }

  const recurrence = parsed.value;
  const freqRaw = recurrence['FREQ'];
  if (!isTaskRecurrenceFrequency(freqRaw)) return null;

  const intervalRaw = recurrence['INTERVAL'];
  let interval: number | undefined;
  if (intervalRaw !== undefined) {
    if (
      typeof intervalRaw !== 'number'
      || !Number.isSafeInteger(intervalRaw)
      || intervalRaw < 1
      || intervalRaw > RECURRENCE_INTERVAL_MAX
    ) {
      return null;
    }
    interval = intervalRaw;
  }

  const untilRaw = recurrence['UNTIL'];
  let until: string | undefined;
  if (untilRaw !== undefined) {
    if (!isCanonicalYmd(untilRaw)) return null;
    until = untilRaw;
  }

  const bydayRaw = recurrence['BYDAY'];
  let byday: TaskRecurrenceWeekdayCode[] | undefined;
  if (bydayRaw !== undefined) {
    if (!Array.isArray(bydayRaw) || !bydayRaw.every(isBydayToken)) return null;
    byday = bydayRaw.filter(isTaskRecurrenceWeekdayCode);
  }

  const hasSimpleByday = bydayRaw === undefined
    || (Array.isArray(bydayRaw) && freqRaw === 'WEEKLY' && bydayRaw.every(isTaskRecurrenceWeekdayCode));
  const editable = hasOnlyKeys(recurrence, SIMPLE_TASK_RECURRENCE_KEYS) && hasSimpleByday;

  return {
    freq: freqRaw,
    editable,
    interval,
    byday: editable ? byday : undefined,
    until,
  };
}

export function taskRecurrencePatchMatchesRaw(
  patch: Exclude<TaskRecurrenceRulePatch, null>,
  raw: string | null | undefined,
): boolean {
  const parsed = parseTaskRecurrence(raw);
  if (!parsed || !parsed.editable) return false;
  if (parsed.freq !== patch.FREQ) return false;
  if ((parsed.interval ?? 1) !== (patch.INTERVAL ?? 1)) return false;
  if ((parsed.until ?? null) !== (patch.UNTIL ?? null)) return false;

  const parsedByday = parsed.byday ?? [];
  const patchByday = patch.BYDAY ?? [];
  if (parsedByday.length !== patchByday.length) return false;
  for (let index = 0; index < patchByday.length; index += 1) {
    if (parsedByday[index] !== patchByday[index]) return false;
  }
  return true;
}
