import { tryParseJson } from '../security/jsonParse';

type PreferenceJsonParseResult =
  | { ok: true; value: unknown }
  | { ok: false };

/** Parse a JSON-stored preference value while preserving invalid-JSON detection. */
export function tryParsePreferenceJson(raw: string | null): PreferenceJsonParseResult {
  if (!raw) {
    return { ok: true, value: null };
  }
  const parsed = tryParseJson(raw);
  if (!parsed.ok) {
    return { ok: false };
  }
  return { ok: true, value: parsed.value };
}

/** Parse a JSON-stored preference value, returning null on empty/invalid input. */
export function parsePreferenceJson(raw: string | null): unknown {
  const result = tryParsePreferenceJson(raw);
  return result.ok ? result.value : null;
}

/** Parse a JSON-stored boolean preference, returning `fallback` when missing/invalid. */
export function parseBooleanPreference(raw: string | null, fallback: boolean = false): boolean {
  const parsed = parsePreferenceJson(raw);
  return typeof parsed === 'boolean' ? parsed : fallback;
}

/** Parse a JSON-stored string preference, returning `fallback` when missing/invalid. */
export function parseStringPreference(raw: string | null, fallback: string): string {
  const parsed = parsePreferenceJson(raw);
  return typeof parsed === 'string' ? parsed : fallback;
}

/** Parse a JSON-stored array of strings, rejecting malformed arrays. */
export function parseStringArrayPreference(raw: string | null): string[] {
  const parsed = parsePreferenceJson(raw);
  if (!Array.isArray(parsed)) return [];
  return parsed.every((item) => typeof item === 'string') ? parsed : [];
}

/** Build a stable parser callback for `usePreference(..., parse)` call sites. */
export function createBooleanPreferenceParser(fallback: boolean) {
  return (raw: string | null): boolean => parseBooleanPreference(raw, fallback);
}
