import { formatCalendarDate, formatDate } from '@/lib/dates/dateLocale';
import { type TranslationKey } from '@/lib/i18n';
import {
  parseTaskRecurrence,
  type TaskRecurrenceFrequency,
  type TaskRecurrenceWeekdayCode,
} from '@/lib/taskRecurrence';
import {
  normalizeRecurrenceIntervalInput,
  normalizeRecurrenceIntervalValue,
} from '@/lib/recurrenceInterval';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';

export interface RecurrenceRule {
  freq: TaskRecurrenceFrequency;
  editable: boolean;
  interval?: number | undefined;
  byday?: TaskRecurrenceWeekdayCode[] | undefined;
  until?: string | undefined;
}

const WEEKDAY_OFFSETS: Record<string, number> = {
  MO: 0,
  TU: 1,
  WE: 2,
  TH: 3,
  FR: 4,
  SA: 5,
  SU: 6,
};
export const FREQ_OPTIONS: Array<{ value: RecurrenceRule['freq']; labelKey: TranslationKey }> = [
  { value: 'DAILY', labelKey: 'task.recurrence.daily' },
  { value: 'WEEKLY', labelKey: 'task.recurrence.weekly' },
  { value: 'MONTHLY', labelKey: 'task.recurrence.monthly' },
  { value: 'YEARLY', labelKey: 'task.recurrence.yearly' },
];

export const BYDAY_OPTIONS: Array<{ code: string; labelKey: TranslationKey }> = [
  { code: 'MO', labelKey: 'weekday.mon' },
  { code: 'TU', labelKey: 'weekday.tue' },
  { code: 'WE', labelKey: 'weekday.wed' },
  { code: 'TH', labelKey: 'weekday.thu' },
  { code: 'FR', labelKey: 'weekday.fri' },
  { code: 'SA', labelKey: 'weekday.sat' },
  { code: 'SU', labelKey: 'weekday.sun' },
];

export type Translator = (key: TranslationKey) => string;
export type SavePatch = (patch: TaskUpdatePatch) => Promise<void>;

export { normalizeRecurrenceIntervalInput, normalizeRecurrenceIntervalValue };

function formatWeekdayLabel(code: string, locale: string): string {
  const offset = WEEKDAY_OFFSETS[code];
  if (offset == null) return code;
  // `formatDate` routes through the shared formatter cache so the
  // recurrence-rule editor can format every weekday code (≤7) without
  // building a fresh `Intl.DateTimeFormat` per code.
  return formatDate(new Date(Date.UTC(2024, 0, 1 + offset)), locale, {
    weekday: 'short',
    timeZone: 'UTC',
  });
}

export function parseRecurrence(raw: string): RecurrenceRule | null {
  return parseTaskRecurrence(raw);
}

// CJK locales don't use spaces between words.
const CJK_LOCALE_PREFIXES = ['zh', 'ja', 'ko'];
function isCjkLocale(locale: string): boolean {
  return CJK_LOCALE_PREFIXES.some((prefix) => locale.startsWith(prefix));
}

export function formatRecurrenceSummary(
  rule: RecurrenceRule,
  everyLabel: string,
  freqLabel: string,
  onLabel: string,
  untilLabel: string,
  locale: string,
  interval?: number,
): string {
  const sep = isCjkLocale(locale) ? '' : ' ';
  const count = interval ?? 1;
  let summary = count > 1 ? `${everyLabel}${sep}${count}${sep}${freqLabel}` : `${everyLabel}${sep}${freqLabel}`;
  if (rule.freq === 'WEEKLY' && rule.byday && rule.byday.length > 0) {
    const daySep = isCjkLocale(locale) ? '、' : ', ';
    const days = rule.byday.map((day) => formatWeekdayLabel(day, locale)).join(daySep);
    summary += `${sep}${onLabel}${sep}${days}`;
  }
  if (rule.until) {
    // `formatCalendarDate` anchors the parse at UTC midnight + forces
    // `timeZone: 'UTC'` so the ymd stays on the same calendar day
    // regardless of host OS timezone vs the app-configured timezone.
    if (!Number.isNaN(new Date(`${rule.until}T00:00:00Z`).getTime())) {
      const formatted = formatCalendarDate(rule.until, locale, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      });
      summary += `${sep}${untilLabel}${sep}${formatted}`;
    }
  }
  return summary;
}
