export interface WallTime {
  date: string;
  time: string;
}

interface WallTimeParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

function parseDatetimeLocal(value: string): WallTimeParts | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(value);
  if (!match) return null;
  const [, yearStr, monthStr, dayStr, hourStr, minuteStr, secondStr] = match;
  return {
    year: Number(yearStr),
    month: Number(monthStr),
    day: Number(dayStr),
    hour: Number(hourStr),
    minute: Number(minuteStr),
    second: secondStr ? Number(secondStr) : 0,
  };
}

function parseWallTime(wall: WallTime): WallTimeParts | null {
  const dateMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(wall.date);
  const timeMatch = /^(\d{1,2}):(\d{2})$/.exec(wall.time);
  if (!dateMatch || !timeMatch) return null;
  const [, yearStr, monthStr, dayStr] = dateMatch;
  const [, hourStr, minuteStr] = timeMatch;
  return {
    year: Number(yearStr),
    month: Number(monthStr),
    day: Number(dayStr),
    hour: Number(hourStr),
    minute: Number(minuteStr),
    second: 0,
  };
}

function wallPartsToNaiveUtcMs(parts: WallTimeParts): number {
  return Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second,
  );
}

/**
 * Return the offset in minutes from UTC at `utcMs` for the given IANA
 * `timeZone`. Positive values are east of UTC.
 */
export function offsetMinutesAt(utcMs: number, timeZone: string): number {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  });
  const parts = formatter.formatToParts(new Date(utcMs));
  const lookup = (type: string) =>
    Number(parts.find((part) => part.type === type)?.value ?? '0');
  const wallAsUtc = Date.UTC(
    lookup('year'),
    lookup('month') - 1,
    lookup('day'),
    lookup('hour'),
    lookup('minute'),
    lookup('second'),
  );
  return Math.round((wallAsUtc - utcMs) / 60_000);
}

function utcMsFromWallTimeParts(parts: WallTimeParts, timeZone: string): number | null {
  const naiveUtc = wallPartsToNaiveUtcMs(parts);
  let utcMs = naiveUtc;
  try {
    utcMs = naiveUtc - offsetMinutesAt(naiveUtc, timeZone) * 60_000;
    utcMs = naiveUtc - offsetMinutesAt(utcMs, timeZone) * 60_000;
  } catch {
    return null;
  }
  return Number.isNaN(utcMs) ? null : utcMs;
}

export function isoFromWallTimeInTimezone(value: string, timeZone: string): string | null {
  const parts = parseDatetimeLocal(value);
  if (!parts) return null;
  const utcMs = utcMsFromWallTimeParts(parts, timeZone);
  if (utcMs == null) return null;
  const date = new Date(utcMs);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function wallTimeFromUtcMs(utcMs: number, timeZone: string): WallTime | null {
  let parts: Intl.DateTimeFormatPart[];
  try {
    parts = new Intl.DateTimeFormat('en-CA', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    }).formatToParts(new Date(utcMs));
  } catch {
    return null;
  }
  const lookup: Record<string, string> = {};
  for (const part of parts) {
    if (part.type !== 'literal') lookup[part.type] = part.value;
  }
  const hour = lookup.hour === '24' ? '00' : lookup.hour;
  if (!lookup.year || !lookup.month || !lookup.day || !hour || !lookup.minute) return null;
  return {
    date: `${lookup.year}-${lookup.month}-${lookup.day}`,
    time: `${hour}:${lookup.minute}`,
  };
}

export function convertWallTimeBetweenTimezones(
  wall: WallTime,
  fromTimeZone: string,
  toTimeZone: string,
): WallTime | null {
  const parts = parseWallTime(wall);
  if (!parts) return null;
  const utcMs = utcMsFromWallTimeParts(parts, fromTimeZone);
  return utcMs == null ? null : wallTimeFromUtcMs(utcMs, toTimeZone);
}
