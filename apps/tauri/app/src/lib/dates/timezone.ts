import {
  convertWallTimeBetweenTimezones,
  type WallTime,
} from './timezoneMath.ts';

const FALLBACK_TIMEZONE_OPTIONS = [
  'UTC',
  'America/Los_Angeles',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'Europe/London',
  'Europe/Berlin',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Singapore',
  'Australia/Sydney',
] as const;

type IntlWithSupportedValuesOf = typeof Intl & {
  supportedValuesOf?: (key: 'timeZone') => string[];
};

export function getSystemTimezone(): string {
  return getRawSystemTimezone() ?? 'UTC';
}

export function getRawSystemTimezone(): string | null {
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  return typeof timezone === 'string' && timezone.trim() !== '' ? timezone : null;
}

export function isValidTimezone(value: unknown): value is string {
  if (typeof value !== 'string' || value.trim() === '') return false;
  // Keep frontend validation aligned with the repo's IANA-only contract.
  // `Intl.DateTimeFormat` accepts raw UTC offsets like `+01:00`, but Rust
  // paths validate timezone names as canonical IANA identifiers.
  if (/^[+-]\d{2}(?::?\d{2})?$/.test(value.trim())) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value }).format(0);
    return true;
  } catch {
    return false;
  }
}

function getBaseTimezoneOptions(): string[] {
  const intlWithSupportedValues = Intl as IntlWithSupportedValuesOf;
  const supportedValues = typeof intlWithSupportedValues.supportedValuesOf === 'function'
    ? intlWithSupportedValues.supportedValuesOf('timeZone')
    : [];
  if (supportedValues.length === 0) {
    return [...FALLBACK_TIMEZONE_OPTIONS];
  }
  return supportedValues.includes('UTC') ? supportedValues : ['UTC', ...supportedValues];
}

export function normalizeTimezonePreference(rawTimezone: unknown, systemTimezone: string): string {
  if (isValidTimezone(rawTimezone)) return rawTimezone;
  return isValidTimezone(systemTimezone) ? systemTimezone : 'UTC';
}

export type { WallTime };

/**
 * Convert a wall-clock `(date, time)` from `fromTz` to `toTz`.
 *
 * Algorithm: treat the wall-clock as if it were UTC to get a guess
 * instant, then iterate twice to land on the actual UTC instant whose
 * `fromTz` representation matches the requested wall-clock. Two passes
 * suffice for any IANA zone except the literal DST gap/overlap minute,
 * which the second pass handles by accepting the offset that `fromTz`
 * actually used at that instant. Then read the wall-clock back in
 * `toTz`.
 *
 * Returns `null` when either zone is invalid — the caller falls back to
 * "Keep absolute" (which is a no-op on the form).
 */
export function convertWallTime(
  wall: WallTime,
  fromTz: string,
  toTz: string,
): WallTime | null {
  if (!isValidTimezone(fromTz) || !isValidTimezone(toTz)) return null;
  return convertWallTimeBetweenTimezones(wall, fromTz, toTz);
}

export function resolveTimezoneOptions(selectedTimezone: string, systemTimezone: string): string[] {
  const baseOptions = getBaseTimezoneOptions();
  const options = [...baseOptions];

  if (isValidTimezone(systemTimezone) && !options.includes(systemTimezone)) {
    options.push(systemTimezone);
  }
  if (isValidTimezone(selectedTimezone) && !options.includes(selectedTimezone)) {
    options.unshift(selectedTimezone);
  }

  return options;
}
