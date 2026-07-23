export type { Locale, TranslationKey } from './registry';
export {
  loadLocale,
  localeRegistry,
  normalizeLocaleCode,
} from './registry';
export {
  detectSystemLocale,
  formatNumber,
  formatPluralTranslation,
  formatTranslation,
  hasLocaleTranslation,
  isValidLocale,
  resolveLocalePreference,
  translate,
} from './runtime';
export type {
  PluralTranslationKeys,
  TranslationVars,
} from './runtime';
