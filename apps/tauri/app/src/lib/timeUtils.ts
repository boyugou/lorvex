import { diffYmdDays } from './dayContextMath';

const CLOCK_TIME_PATTERN = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

export function parseTimeToMinutes(hhmm: string | null | undefined): number | null {
  if (typeof hhmm !== 'string') return null;
  const trimmed = hhmm.trim();
  if (!CLOCK_TIME_PATTERN.test(trimmed)) return null;
  const [hourPart = '0', minutePart = '0'] = trimmed.split(':');
  const hours = Number(hourPart);
  const minutes = Number(minutePart);
  return hours * 60 + minutes;
}

/** Convert "HH:MM" time string to total minutes since midnight. */
export function timeToMinutes(hhmm: string): number {
  return parseTimeToMinutes(hhmm) ?? 0;
}

/** Days between two YYYY-MM-DD date strings. Positive if b is after a. */
export function daysBetween(a: string, b: string): number {
  return diffYmdDays(a, b);
}
