import { createBooleanPreferenceParser } from '../preferences/parser';
import { tryParseJson } from '../security/jsonParse';
import { preferenceQueryKey, type PreferenceQueryKey } from './preferenceCache';
import { STALE_DEFAULT } from './timing';

interface PreferenceQueryConfig {
  queryKey: PreferenceQueryKey;
  staleTime: number;
  enabled?: boolean;
}

export function buildPreferenceQueryConfig(args: {
  key: string;
  staleTime?: number;
  enabled?: boolean;
}): PreferenceQueryConfig {
  const config: PreferenceQueryConfig = {
    queryKey: preferenceQueryKey(args.key),
    staleTime: args.staleTime ?? STALE_DEFAULT,
  };
  if (args.enabled !== undefined) {
    config.enabled = args.enabled;
  }
  return config;
}

export function assertValidPreferenceWriteValue(key: string, nextValue: unknown): void {
  if (typeof nextValue === 'number' && !Number.isFinite(nextValue)) {
    throw new Error(`preference '${key}' rejected non-finite number`);
  }
}

export function encodePreferenceCacheValue(nextValue: unknown): string | null {
  return nextValue == null ? null : JSON.stringify(nextValue);
}

/** Parse a boolean preference. Returns `defaultValue` when the raw value is null or invalid JSON. */
export function parseBool(defaultValue: boolean) {
  return createBooleanPreferenceParser(defaultValue);
}

/**
 * Parse a primitive JSON preference, returning `defaultValue` on null/invalid.
 *
 * `JSON.parse` returns `any`, so a bare `as T` cast allowed
 * any stored value of the wrong shape to flow through silently. For
 * primitive defaults (boolean, number, string), a `typeof` check against the
 * default gives runtime validation "for free". Structural defaults (arrays,
 * objects) intentionally fail closed; callers must use `parseJsonValidated`
 * with an explicit type guard.
 */
export function parseJson<T>(defaultValue: T) {
  return (raw: string | null): T => {
    if (raw === null) return defaultValue;
    const parseResult = tryParseJson(raw);
    if (!parseResult.ok) return defaultValue;
    const parsed = parseResult.value;
    const expectedType = typeof defaultValue;
    if (expectedType === 'boolean' || expectedType === 'number' || expectedType === 'string') {
      if (typeof parsed !== expectedType) return defaultValue;
      return parsed as T;
    }
    if (defaultValue === null && parsed === null) {
      return defaultValue;
    }
    return defaultValue;
  };
}

/**
 * Parse an integer-valued scalar preference with strict bounds.
 *
 * - `defaultValue` is returned for null, non-decimal integer,
 *   non-finite, unsafe-integer, and out-of-range values.
 * - `min` and `max` are inclusive. Default: `min = 0`,
 *   `max = Number.MAX_SAFE_INTEGER`.
 */
export function parseIntegerInRange(
  defaultValue: number,
  min: number = 0,
  max: number = Number.MAX_SAFE_INTEGER,
) {
  return (raw: string | null): number => {
    if (raw === null) return defaultValue;
    if (!/^-?\d+$/.test(raw)) return defaultValue;
    const parsed = Number(raw);
    if (!Number.isSafeInteger(parsed)) return defaultValue;
    if (parsed < min || parsed > max) return defaultValue;
    return parsed;
  };
}

/** Parse a JSON preference with an explicit runtime type guard. */
export function parseJsonValidated<T>(
  defaultValue: T,
  guard: (value: unknown) => value is T,
) {
  return (raw: string | null): T => {
    if (raw === null) return defaultValue;
    const parseResult = tryParseJson(raw);
    if (!parseResult.ok) return defaultValue;
    return guard(parseResult.value) ? parseResult.value : defaultValue;
  };
}

/** Return the raw string, or a default when null. */
export function parseString(defaultValue: string) {
  return (raw: string | null): string => {
    if (raw === null) return defaultValue;
    const parseResult = tryParseJson(raw);
    if (!parseResult.ok) return defaultValue;
    return typeof parseResult.value === 'string' ? parseResult.value : defaultValue;
  };
}
