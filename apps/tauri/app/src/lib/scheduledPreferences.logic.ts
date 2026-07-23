const SCHEDULE_WEEKDAY_VALUES = [
  'sunday',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
] as const;

type ScheduleWeekday = (typeof SCHEDULE_WEEKDAY_VALUES)[number];

const SCHEDULE_WEEKDAY_SET = new Set<ScheduleWeekday>(SCHEDULE_WEEKDAY_VALUES);
const SCHEDULE_TIME_PATTERN = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

export function normalizeScheduledTimePreference(value: unknown, fallback: string): string {
  if (typeof value !== 'string') return fallback;
  const normalized = value.trim();
  return SCHEDULE_TIME_PATTERN.test(normalized) ? normalized : fallback;
}

export function normalizeScheduledWeekdayPreference(value: unknown, fallback: string): string {
  if (typeof value !== 'string') return fallback;
  const normalized = value.trim().toLowerCase();
  return SCHEDULE_WEEKDAY_SET.has(normalized as ScheduleWeekday) ? normalized : fallback;
}
