import { formatDate } from '@/lib/dates/dateLocale';

const CANONICAL_HH_MM = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

interface ParsedClockTime {
  hour: number;
  minute: number;
}

export function parseCanonicalClockTime(value: string): ParsedClockTime | null {
  if (!CANONICAL_HH_MM.test(value)) return null;
  const [hourRaw, minuteRaw] = value.split(':');
  return {
    hour: Number(hourRaw),
    minute: Number(minuteRaw),
  };
}

/** Format HH:MM for display, locale-aware (12h AM/PM for English, 24h otherwise). */
export function formatTimeDisplay(hhmm: string, locale: string): string {
  const parsed = parseCanonicalClockTime(hhmm);
  if (!parsed) return hhmm;

  try {
    const date = new Date(2000, 0, 1, parsed.hour, parsed.minute);
    // `formatDate` routes through the shared formatter cache so high-
    // frequency renders (settings panels with multiple HH:MM rows) reuse
    // a single `Intl.DateTimeFormat` per locale across the whole list.
    return formatDate(date, locale, { hour: 'numeric', minute: '2-digit' });
  } catch {
    return hhmm;
  }
}
