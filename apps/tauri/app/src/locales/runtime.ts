import {
  fallbackTranslations,
  localeMap,
  localeRegistry,
  normalizeLocaleCode,
  type Locale,
  type TranslationKey,
} from './registry';
import { parseStringPreference } from '../lib/preferences/parser';

/** Set of all supported locale codes, derived from the registry at module init. */
const supportedCodes: ReadonlySet<string> = new Set(localeRegistry.map((entry) => entry.code));
// `Intl.NumberFormat` and `Intl.PluralRules` are both
// non-trivial to construct (each call walks the runtime's CLDR locale
// data), so we cache one instance per locale at module scope rather
// than allocating fresh instances on every `formatTranslation` /
// `formatPluralTranslation` invocation. Plural / number formatting is
// hit on every render of every list view; the per-render allocation
// cost showed up in React Profiler under `UpcomingView` for users with
// hundreds of tasks. The cache key is the bare locale string — locales
// are a closed set (`localeRegistry`), so the map never grows
// unboundedly.
const numberFormatterCache = new Map<string, Intl.NumberFormat>();
const pluralRulesCache = new Map<string, Intl.PluralRules>();
const PLACEHOLDER_PATTERN = /\{(\w+)\}/g;

export type TranslationPrimitive = string | number | boolean | null | undefined;
export type TranslationVars = Record<string, TranslationPrimitive>;
export type PluralCategory = Intl.LDMLPluralRule;
export type PluralTranslationKeys = Partial<Record<PluralCategory, TranslationKey>> & {
  other: TranslationKey;
};

export function translate(locale: string, key: TranslationKey): string {
  const table = localeMap.get(locale);
  return table?.[key] ?? fallbackTranslations[key] ?? key;
}

export function isValidLocale(code: string): code is Locale {
  return supportedCodes.has(code);
}

export function detectSystemLocale(): Locale {
  if (typeof navigator === 'undefined') return 'en';
  const candidates = [
    ...(Array.isArray(navigator.languages) ? navigator.languages : []),
    navigator.language,
  ]
    .filter((value): value is string => typeof value === 'string' && value.trim().length > 0);

  for (const raw of candidates) {
    const normalized = raw.trim().toLowerCase().replaceAll('_', '-');
    const exact = normalizeLocaleCode(normalized);
    if (exact) return exact;

    const parts = normalized.split('-').filter(Boolean);
    for (let length = parts.length - 1; length >= 1; length -= 1) {
      const parentLocale = normalizeLocaleCode(parts.slice(0, length).join('-'));
      if (parentLocale) return parentLocale;
    }
  }

  return 'en';
}

function getNumberFormatter(locale: string): Intl.NumberFormat {
  const cached = numberFormatterCache.get(locale);
  if (cached) return cached;

  let formatter: Intl.NumberFormat;
  try {
    formatter = new Intl.NumberFormat(locale);
  } catch {
    formatter = new Intl.NumberFormat('en');
  }

  numberFormatterCache.set(locale, formatter);
  return formatter;
}

function getPluralRules(locale: string): Intl.PluralRules {
  const cached = pluralRulesCache.get(locale);
  if (cached) return cached;

  let rules: Intl.PluralRules;
  try {
    rules = new Intl.PluralRules(locale);
  } catch {
    rules = new Intl.PluralRules('en');
  }

  pluralRulesCache.set(locale, rules);
  return rules;
}

export function formatNumber(locale: string, value: number): string {
  return getNumberFormatter(locale).format(value);
}

function formatTranslationVar(locale: string, value: TranslationPrimitive): string {
  if (typeof value === 'number') return formatNumber(locale, value);
  if (typeof value === 'boolean') return String(value);
  if (value == null) return '';
  return value;
}

export function formatTranslation(locale: string, key: TranslationKey, vars: TranslationVars = {}): string {
  const template = translate(locale, key);
  return template.replace(PLACEHOLDER_PATTERN, (match, name: string) => {
    if (!(name in vars)) return match;
    return formatTranslationVar(locale, vars[name]);
  });
}

export function hasLocaleTranslation(locale: string, key: TranslationKey): boolean {
  const table = localeMap.get(locale);
  return typeof table?.[key] === 'string';
}

function resolvePluralCategory(locale: string, count: number): PluralCategory {
  return getPluralRules(locale).select(count);
}

function resolveLocalePluralKey(
  locale: string,
  count: number,
  keys: PluralTranslationKeys,
): TranslationKey | null {
  const category = resolvePluralCategory(locale, count);
  const candidates = [
    keys[category],
    keys.other,
    keys.one,
    keys.few,
    keys.many,
  ].filter((candidate): candidate is TranslationKey => candidate != null);

  for (const candidate of candidates) {
    if (hasLocaleTranslation(locale, candidate)) return candidate;
  }

  return null;
}

function resolveFallbackPluralKey(count: number, keys: PluralTranslationKeys): TranslationKey {
  // When we fall back to English source strings, we must choose the
  // English plural arm rather than reusing the target locale's plural
  // category. Otherwise locales like French (where 0 => "one") select
  // singular English templates such as "0 task".
  const category = resolvePluralCategory('en', count);
  return keys[category] ?? keys.other;
}

export function formatPluralTranslation(
  locale: string,
  count: number,
  keys: PluralTranslationKeys,
  vars: TranslationVars = {},
  options: { fallback?: ((formattedCount: string) => string) | undefined } = {},
): string {
  const localeKey = resolveLocalePluralKey(locale, count, keys);
  if (localeKey) {
    return formatTranslation(locale, localeKey, { count, ...vars });
  }
  if (options.fallback) {
    return options.fallback(formatNumber(locale, count));
  }
  return formatTranslation(locale, resolveFallbackPluralKey(count, keys), {
    count,
    ...vars,
  });
}

export function resolveLocalePreference(raw: string | null): { locale: Locale; usingSystemLocale: boolean } {
  const persisted = parseStringPreference(raw, '');
  const persistedLocale = persisted ? normalizeLocaleCode(persisted) : null;
  if (persistedLocale) {
    return { locale: persistedLocale, usingSystemLocale: false };
  }

  return {
    locale: detectSystemLocale(),
    usingSystemLocale: true,
  };
}
