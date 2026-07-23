import {
  loadLocale,
  normalizeLocaleCode,
  resolveLocalePreference,
  translate,
  type TranslationKey,
} from '@/locales';
import { parseStringPreference } from '../preferences/parser';
import {
  normalizeScheduledTimePreference,
  normalizeScheduledWeekdayPreference,
} from '../scheduledPreferences.logic';

export function parseTimePreference(raw: string | null, fallback: string): string {
  return normalizeScheduledTimePreference(parseStringPreference(raw, fallback), fallback);
}

export function parseWeekdayPreference(raw: string | null, fallback: string): string {
  return normalizeScheduledWeekdayPreference(parseStringPreference(raw, fallback), fallback);
}

export function resolveNotificationLocale(raw: string | null): string {
  return resolveLocalePreference(raw).locale;
}

/**
 * Load the locale's translations (if not already cached) and return a
 * synchronous translator function. Call sites are already async, so the
 * one-time dynamic import is transparent.
 */
export async function translatorFor(locale: string) {
  const canonicalLocale = normalizeLocaleCode(locale) ?? 'en';
  await loadLocale(canonicalLocale);
  return (key: TranslationKey): string => translate(canonicalLocale, key);
}
