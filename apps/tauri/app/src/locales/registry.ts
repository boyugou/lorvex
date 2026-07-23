/**
 * Locale registry and static catalog ownership.
 *
 * Only English is eagerly imported (it defines the synchronous fallback
 * the renderer uses on first paint). All other locales are loaded on
 * demand via loadLocale(); Vite/Rolldown emit one chunk per JSON file
 * (see manualChunks in app/vite.config.ts).
 *
 * Catalogs live in `app/src/locales/<code>.json`. The `_invariant.json`
 * catalog carries cross-locale-shared keys (proper nouns, schema
 * discriminators, format patterns) — it is spread into every locale
 * after dynamic load so each locale JSON can stay purely the
 * translator-managed delta against English.
 *
 * The `TranslationKey` type is codegen'd from `en.json` into
 * `types.generated.ts` — regenerate via
 * `node scripts/generate/locale_types.mjs` after editing en.json.
 *
 * To add a new language:
 *   1. Create `app/src/locales/<code>.json` with a partial translation object
 *   2. Add one entry to `localeRegistry` below, including its dynamic loader
 *   That's it. Missing keys automatically fall back to English.
 */
import enJson from './en.json';
import invariantJson from './_invariant.json';
import type { TranslationKey } from './types.generated';

export type { TranslationKey };
export type LocaleTextDirection = 'ltr' | 'rtl';
type LocaleTranslations = Partial<Record<TranslationKey, string>>;
export interface LocaleDefinition {
  code: string;
  label: string;
  dir: LocaleTextDirection;
  load: () => Promise<LocaleTranslations>;
}

// `as const` would require a const-assertion on the JSON import which
// TS doesn't support yet for `with { type: 'json' }`. Cast through
// `unknown` once at the boundary; downstream uses the typed alias.
const en = enJson as unknown as Record<TranslationKey, string>;
const INVARIANT = invariantJson as unknown as LocaleTranslations;

function catalog(loader: () => Promise<{ default: LocaleTranslations }>): () => Promise<LocaleTranslations> {
  // Spread INVARIANT into every dynamically loaded locale so the
  // wire-format JSON files can stay purely the translator-managed
  // delta against English.
  return () => loader().then((module) => ({ ...INVARIANT, ...module.default }));
}

export const localeRegistry = [
  { code: 'en', label: 'English', dir: 'ltr', load: async () => en },
  { code: 'zh', label: '中文', dir: 'ltr', load: catalog(() => import('./zh.json')) },
  { code: 'zh-Hant', label: '繁體中文', dir: 'ltr', load: catalog(() => import('./zh-Hant.json')) },
  { code: 'es', label: 'Español', dir: 'ltr', load: catalog(() => import('./es.json')) },
  { code: 'fr', label: 'Français', dir: 'ltr', load: catalog(() => import('./fr.json')) },
  { code: 'de', label: 'Deutsch', dir: 'ltr', load: catalog(() => import('./de.json')) },
  { code: 'ja', label: '日本語', dir: 'ltr', load: catalog(() => import('./ja.json')) },
  { code: 'ko', label: '한국어', dir: 'ltr', load: catalog(() => import('./ko.json')) },
  { code: 'pt', label: 'Português', dir: 'ltr', load: catalog(() => import('./pt.json')) },
  { code: 'ru', label: 'Русский', dir: 'ltr', load: catalog(() => import('./ru.json')) },
  { code: 'hi', label: 'हिन्दी', dir: 'ltr', load: catalog(() => import('./hi.json')) },
  { code: 'ar', label: 'العربية', dir: 'rtl', load: catalog(() => import('./ar.json')) },
  { code: 'id', label: 'Bahasa Indonesia', dir: 'ltr', load: catalog(() => import('./id.json')) },
  { code: 'it', label: 'Italiano', dir: 'ltr', load: catalog(() => import('./it.json')) },
  { code: 'nl', label: 'Nederlands', dir: 'ltr', load: catalog(() => import('./nl.json')) },
  { code: 'tr', label: 'Türkçe', dir: 'ltr', load: catalog(() => import('./tr.json')) },
  { code: 'pl', label: 'Polski', dir: 'ltr', load: catalog(() => import('./pl.json')) },
  { code: 'uk', label: 'Українська', dir: 'ltr', load: catalog(() => import('./uk.json')) },
  { code: 'vi', label: 'Tiếng Việt', dir: 'ltr', load: catalog(() => import('./vi.json')) },
  { code: 'th', label: 'ไทย', dir: 'ltr', load: catalog(() => import('./th.json')) },
  { code: 'ms', label: 'Bahasa Melayu', dir: 'ltr', load: catalog(() => import('./ms.json')) },
  { code: 'bn', label: 'বাংলা', dir: 'ltr', load: catalog(() => import('./bn.json')) },
  { code: 'te', label: 'తెలుగు', dir: 'ltr', load: catalog(() => import('./te.json')) },
  { code: 'mr', label: 'मराठी', dir: 'ltr', load: catalog(() => import('./mr.json')) },
  { code: 'ta', label: 'தமிழ்', dir: 'ltr', load: catalog(() => import('./ta.json')) },
  { code: 'ml', label: 'മലയാളം', dir: 'ltr', load: catalog(() => import('./ml.json')) },
  { code: 'el', label: 'Ελληνικά', dir: 'ltr', load: catalog(() => import('./el.json')) },
  { code: 'ro', label: 'Română', dir: 'ltr', load: catalog(() => import('./ro.json')) },
  { code: 'ur', label: 'اردو', dir: 'rtl', load: catalog(() => import('./ur.json')) },
  { code: 'fa', label: 'فارسی', dir: 'rtl', load: catalog(() => import('./fa.json')) },
  { code: 'he', label: 'עברית', dir: 'rtl', load: catalog(() => import('./he.json')) },
] as const satisfies readonly LocaleDefinition[];
export type Locale = (typeof localeRegistry)[number]['code'];

const localeByNormalizedCode = new Map<string, Locale>(
  localeRegistry.map((entry) => [entry.code.toLowerCase(), entry.code]),
);
const localeDirectionByCode = new Map<Locale, LocaleTextDirection>(
  localeRegistry.map((entry) => [entry.code, entry.dir]),
);
const localeDefinitionByCode = new Map<Locale, LocaleDefinition>(
  localeRegistry.map((entry) => [entry.code, entry]),
);

export function normalizeLocaleCode(code: string): Locale | null {
  const normalized = code.trim().toLowerCase().replaceAll('_', '-');
  return localeByNormalizedCode.get(normalized) ?? null;
}

export function localeTextDirection(locale: Locale): LocaleTextDirection {
  return localeDirectionByCode.get(locale) ?? 'ltr';
}

/**
 * Mutable locale translation cache. Starts with only English; other locales are
 * populated on demand via loadLocale().
 */
export const localeMap = new Map<string, Partial<Record<TranslationKey, string>>>([
  ['en', en],
]);

export const fallbackTranslations: Record<TranslationKey, string> = en;

/**
 * Dynamically import a locale's translations and cache them in localeMap.
 * Returns the translations (empty object for unknown codes).
 * English is returned synchronously from the cache.
 */
export async function loadLocale(code: string): Promise<Partial<Record<TranslationKey, string>>> {
  const canonicalCode = normalizeLocaleCode(code);
  if (!canonicalCode) return {};

  const cached = localeMap.get(canonicalCode);
  if (cached) return cached;

  const translations = await localeDefinitionByCode.get(canonicalCode)?.load();
  if (!translations) return {};
  localeMap.set(canonicalCode, translations);
  return translations;
}
