import { formatNumber } from '../../locales';
import { normalizeLocaleCode } from '../../locales/registry';
import { readBrowserLocale } from './dateLocale.runtime';
import { isoFromWallTimeInTimezone } from './timezoneMath';

function localeRegion(locale: string): string {
  const subtags = locale.toUpperCase().split('-').slice(1);
  return subtags.find((subtag) => /^[A-Z]{2}$/.test(subtag) || /^\d{3}$/.test(subtag)) ?? '';
}

function intlWeekInfoToDayIndex(firstDay: number): number {
  return firstDay === 7 ? 0 : firstDay;
}

function normalizeWeekStartDayIndex(startDay: number): number {
  return Number.isInteger(startDay) && startDay >= 0 && startDay <= 6 ? startDay : 0;
}

export function parseWeekStartDayPreference(raw: string | null, fallback: number): number {
  if (raw == null) return fallback;
  if (!/^[0-6]$/.test(raw)) return fallback;
  return Number(raw);
}

export function localizedWeekdayOptions(
  locale: string,
  startDay: number,
  format: 'short' | 'long' | 'narrow' = 'short',
): Array<{ dayIndex: number; label: string }> {
  const dateLocale = resolveDateLocale(locale);
  const formatter = new Intl.DateTimeFormat(dateLocale, { weekday: format });
  const sunday = new Date(2024, 0, 7);
  const labels = Array.from({ length: 7 }, (_, index) => {
    const date = new Date(sunday);
    date.setDate(sunday.getDate() + index);
    return {
      dayIndex: index,
      label: formatter.format(date),
    };
  });
  const normalizedStartDay = normalizeWeekStartDayIndex(startDay);
  return [...labels.slice(normalizedStartDay), ...labels.slice(0, normalizedStartDay)];
}

/**
 * Derive the default week start day from the system/browser locale.
 * Returns 0 for Sunday, 1 for Monday, through 6 for Saturday.
 * Uses Intl.Locale.prototype.getWeekInfo (or weekInfo) where available,
 * otherwise falls back to a short static list of Sunday-/Saturday-start regions.
 */
export function localeWeekStartDay(): number {
  try {
    const loc = new Intl.Locale(readBrowserLocale()) as Intl.Locale & {
      getWeekInfo?: () => { firstDay?: number };
      weekInfo?: { firstDay?: number };
    };
    // getWeekInfo() is the standard method (Chrome 99+, Safari 17.4+)
    // weekInfo is the older non-standard property (Safari 15.4–17.3)
    const info: { firstDay?: number } | undefined =
      typeof loc.getWeekInfo === 'function'
        ? loc.getWeekInfo()
        : loc.weekInfo;
    if (info?.firstDay != null) {
      // Intl uses 1=Mon..7=Sun; convert 7 -> 0 for our 0=Sun convention.
      if (info.firstDay >= 1 && info.firstDay <= 7) {
        return intlWeekInfoToDayIndex(info.firstDay);
      }
    }
  } catch { /* Intl.Locale unavailable */ }

  // Fallback: regions that conventionally start weeks on Sunday/Saturday.
  const region = localeRegion(readBrowserLocale());
  const sundayRegions = new Set(['US', 'CA', 'JP', 'IL', 'KR', 'TW', 'PH', 'TH', 'SA']);
  const saturdayRegions = new Set(['AF', 'IR']);
  if (saturdayRegions.has(region)) return 6;
  if (sundayRegions.has(region)) return 0;
  return 1;
}

// Memoized locale resolver. The body constructs `new
// Intl.DateTimeFormat(normalizedLocale)` purely to test validity (the
// formatter is discarded), which is non-trivial. Call sites in
// per-row render paths (task lists, calendar grids) hit this many
// times per render with the same input, so cache the resolved
// locale by raw input string.
//
// The cache is bounded by the set of distinct raw locale inputs
// (~30-40 — the 31 shipped app locales plus the handful of system /
// browser variants normalized down). No eviction needed.
const localeResolutionCache = new Map<string, string>();

export function resolveDateLocale(locale: string): string {
  const cached = localeResolutionCache.get(locale);
  if (cached !== undefined) return cached;

  const canonicalLocale = normalizeDateLocaleInput(locale);
  const normalizedLocale = canonicalLocale === 'zh' ? 'zh-CN' : canonicalLocale;
  let resolved: string;
  try {
    new Intl.DateTimeFormat(normalizedLocale);
    resolved = normalizedLocale;
  } catch {
    resolved = 'en-US';
  }
  localeResolutionCache.set(locale, resolved);
  return resolved;
}

function normalizeDateLocaleInput(locale: string): string {
  const normalized = locale.trim().toLowerCase().replaceAll('_', '-');
  const exact = normalizeLocaleCode(normalized);
  if (exact) return exact;

  const subtags = normalized.split('-').filter(Boolean);
  for (let length = subtags.length - 1; length >= 1; length -= 1) {
    const candidate = normalizeLocaleCode(subtags.slice(0, length).join('-'));
    if (candidate) return candidate;
  }

  return locale;
}

// ---------------------------------------------------------------------------
// Memoized `Intl.DateTimeFormat` cache
// ---------------------------------------------------------------------------
// Constructing an `Intl.DateTimeFormat` walks ICU data and is expensive
// enough that high-frequency renders (calendar grids with N days × M
// events, task lists with M tasks × K timestamp fields) measurably suffer
// when the formatter is built inline at each call site. Memoize per
// `(locale, options-shape)` pair; `Intl.DateTimeFormat` instances are
// thread-safe and reusable.
//
// Cache key uses a stable JSON serialization of the canonical option
// keys; we sort the keys so `{ year, month }` and `{ month, year }`
// produce the same key. The set of recognized option keys is bounded
// (Intl spec — locale, weekday, era, year, month, day, hour, minute,
// second, dayPeriod, fractionalSecondDigits, hour12, hourCycle, calendar,
// numberingSystem, timeZone, timeZoneName, dateStyle, timeStyle,
// formatMatcher) so the cache size is bounded by realistic usage.
const formatterCache = new Map<string, Intl.DateTimeFormat>();
const FORMATTER_OPTION_KEYS = [
  'calendar',
  'dateStyle',
  'day',
  'dayPeriod',
  'era',
  'formatMatcher',
  'fractionalSecondDigits',
  'hour',
  'hour12',
  'hourCycle',
  'minute',
  'month',
  'numberingSystem',
  'second',
  'timeStyle',
  'timeZone',
  'timeZoneName',
  'weekday',
  'year',
] as const;

function buildFormatterCacheKey(
  dateLocale: string,
  options: Intl.DateTimeFormatOptions,
): string {
  // Stable canonical JSON for the options object — only the recognized
  // keys are emitted, in alphabetical order, so semantically-equal
  // option shapes hash to the same key regardless of caller-passed
  // property order or unrelated stray fields.
  const canonical: Record<string, unknown> = {};
  for (const key of FORMATTER_OPTION_KEYS) {
    const value = options[key];
    if (value !== undefined) {
      canonical[key] = value;
    }
  }
  return `${dateLocale}|${JSON.stringify(canonical)}`;
}

function getFormatter(
  dateLocale: string,
  options: Intl.DateTimeFormatOptions,
): Intl.DateTimeFormat {
  const key = buildFormatterCacheKey(dateLocale, options);
  let formatter = formatterCache.get(key);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat(dateLocale, options);
    formatterCache.set(key, formatter);
  }
  return formatter;
}

/**
 * Format an ISO timestamp (e.g. `task.created_at`, `last_fetched_at`) in the
 * user's resolved date-locale and timezone. Equivalent to the inline
 * `new Date(iso).toLocaleString(resolveDateLocale(locale), { timeZone })`
 * pattern that was duplicated 30+ times across components — collapsing to
 * one helper keeps locale + timezone resolution consistent AND amortizes
 * the `Intl.DateTimeFormat` construction via the shared cache above.
 *
 * `options` are merged on top of `{ timeZone }` so callers can request
 * specific shapes (`dateStyle: 'medium'`, `hour: '2-digit'`, etc.).
 */
export function formatTimestamp(
  iso: string,
  locale: string,
  timezone?: string,
  options: Intl.DateTimeFormatOptions = {},
): string {
  const merged: Intl.DateTimeFormatOptions = {
    ...(timezone ? { timeZone: timezone } : {}),
    ...options,
  };
  return getFormatter(resolveDateLocale(locale), merged).format(new Date(iso));
}

/**
 * Format a calendar `YYYY-MM-DD` string in the user's resolved date-locale,
 * anchored to UTC midnight so the printed date never drifts by a day for
 * users east of UTC. Equivalent to the inline
 * ``new Date(`${ymd}T00:00:00Z`).toLocaleDateString(resolveDateLocale(locale), { timeZone: 'UTC', ... })``
 * pattern that was duplicated 20+ times across the calendar, task-detail,
 * weekly-review, and daily-review surfaces.
 *
 * Defaults to `{ month: 'short', day: 'numeric' }` (the most common shape in
 * the codebase). Callers that need weekday or year-aware formats override
 * via `options`.
 */
export function formatCalendarDate(
  ymd: string,
  locale: string,
  options: Intl.DateTimeFormatOptions = { month: 'short', day: 'numeric' },
): string {
  const merged: Intl.DateTimeFormatOptions = { timeZone: 'UTC', ...options };
  return getFormatter(resolveDateLocale(locale), merged).format(
    new Date(`${ymd}T00:00:00Z`),
  );
}

/**
 * Format a calendar `YYYY-MM-DD` as that day in a specific IANA timezone.
 *
 * Unlike [`formatCalendarDate`], this keeps the caller's timezone in the
 * formatter options. The date is anchored at local noon inside `timezone`
 * before formatting, so extreme positive/negative offsets cannot shift the
 * label to the previous or next calendar day.
 */
export function formatCalendarDateInTimeZone(
  ymd: string,
  locale: string,
  timezone: string,
  options: Intl.DateTimeFormatOptions = { month: 'short', day: 'numeric' },
): string {
  const iso = isoFromWallTimeInTimezone(`${ymd}T12:00`, timezone)
    ?? `${ymd}T12:00:00Z`;
  const merged: Intl.DateTimeFormatOptions = { timeZone: timezone, ...options };
  return getFormatter(resolveDateLocale(locale), merged).format(new Date(iso));
}

/**
 * Format a `Date` object in the user's resolved date-locale.
 *
 * Use this when the caller has already constructed a `Date` via math
 * (week-boundary computation, calendar-grid month-start, year/month
 * navigation in the date picker, etc.) — for ISO strings or YYYY-MM-DD
 * strings, prefer [`formatTimestamp`] / [`formatCalendarDate`] which
 * handle the parsing.
 *
 * The formatter is shared with `formatTimestamp` / `formatCalendarDate`
 * via the same `(locale, options-shape)` cache, so a calendar view that
 * formats hundreds of dates per month with the same option object pays
 * one `Intl.DateTimeFormat` construction across the whole render.
 */
export function formatDate(
  date: Date,
  locale: string,
  options: Intl.DateTimeFormatOptions = {},
): string {
  return getFormatter(resolveDateLocale(locale), options).format(date);
}

/**
 * Reset the memoized formatter + locale-resolution caches. Test-only —
 * exposes a seam so unit tests that swap `Intl` polyfills or reset the
 * runtime mid-suite get a deterministic starting point. Production code
 * never calls this; the caches are intentionally process-lived.
 */
export function _resetDateFormatterCacheForTests(): void {
  formatterCache.clear();
  localeResolutionCache.clear();
}

type RelativeTimeKey =
  | 'time.justNow'
  | 'time.minutesAgo'
  | 'time.hoursAgo'
  | 'time.daysAgo'
  | 'time.inMinutes'
  | 'time.inHours'
  | 'time.inDays';

/**
 * Format a timestamp as a relative string such as "just now", "3 minutes
 * ago", or "in 2 hours". Handles both past and future timestamps.
 *
 * delegates to \`Intl.RelativeTimeFormat\` for a locale-aware
 * result with matching past/future grammar. Falls back to compact
 * template strings (\`{value}m ago\` / \`in {value}m\`) when
 * Intl.RelativeTimeFormat is unavailable or errors.
 *
 * Falls back to an absolute locale date for magnitudes >= 7 days in
 * either direction. Pass the user's configured \`timezone\` so the
 * fallback day reflects the user's wall-clock, not the OS tz
 *.
 */
export function formatRelativeTime(
  iso: string,
  locale: string,
  t: (k: RelativeTimeKey) => string,
  format: (k: RelativeTimeKey, vars: { value: string }) => string,
  timezone?: string,
): string {
  // Guard against malformed / empty ISO strings: a NaN parse would
  // skip every ordered comparison below and fall through to
  // `toLocaleDateString`, which on Chromium emits the literal
  // 'Invalid Date'. Render a stable user-facing fallback instead
  // so UIs + accessibility announcements don't surface a
  // corrupt-data signal as a timestamp.
  const parsedMs = new Date(iso).getTime();
  if (!Number.isFinite(parsedMs)) {
    return t('time.justNow');
  }
  const diffMs = Date.now() - parsedMs;
  const isFuture = diffMs < 0;
  const absMs = Math.abs(diffMs);
  const mins = Math.floor(absMs / 60000);
  const dateLocale = resolveDateLocale(locale);

  if (mins < 1) return t('time.justNow');

  const hours = Math.floor(mins / 60);
  const days = Math.floor(hours / 24);
  const sign = isFuture ? 1 : -1;

  // >= 7 days in either direction → absolute date.
  if (days >= 7) {
    return new Date(iso).toLocaleDateString(dateLocale, {
      month: 'short',
      day: 'numeric',
      ...(timezone ? { timeZone: timezone } : {}),
    });
  }

  // Prefer Intl.RelativeTimeFormat — locale-aware and symmetric between
  // past and future. Most consumers use 'narrow' style to match the
  // compact relative-time fallback shape.
  try {
    const rtf = new Intl.RelativeTimeFormat(dateLocale, {
      numeric: 'always',
      style: 'narrow',
    });
    if (days >= 1) return rtf.format(sign * days, 'day');
    if (hours >= 1) return rtf.format(sign * hours, 'hour');
    return rtf.format(sign * mins, 'minute');
  } catch {
    // Fall through to compact i18n templates on non-supporting runtime.
  }

  if (mins < 60) {
    const formattedMinutes = formatNumber(locale, mins);
    return isFuture
      ? format('time.inMinutes', { value: formattedMinutes })
      : `${formattedMinutes}${t('time.minutesAgo')}`;
  }
  if (hours < 24) {
    const formattedHours = formatNumber(locale, hours);
    return isFuture
      ? format('time.inHours', { value: formattedHours })
      : `${formattedHours}${t('time.hoursAgo')}`;
  }
  const formattedDays = formatNumber(locale, days);
  return isFuture
    ? format('time.inDays', { value: formattedDays })
    : `${formattedDays}${t('time.daysAgo')}`;
}
