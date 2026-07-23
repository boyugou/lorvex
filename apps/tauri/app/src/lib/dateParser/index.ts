/**
 * Natural-language date extraction for Quick Capture.
 *
 * Uses chrono-node for multi-language date parsing. Supported locales with
 * dedicated parsers: en, de, es, fr, it, ja, nl, pt, ru, sv, uk, zh, zh-Hant.
 * All other locales fall back to the English casual parser which still catches
 * ISO dates (2026-03-28), relative dates (tomorrow, next week), and numeric
 * date formats (3/28, 03-28).
 */
import * as chrono from 'chrono-node';
import type { ParseResult } from './types';

export type { ParseResult } from './types';

/**
 * Map app locale codes to chrono-node locale modules.
 * chrono-node ships: en, de, es, fr, it, ja, nl, pt, ru, sv, uk, zh
 * Our "zh-Hant" maps to chrono's zh (which includes both hans and hant parsers).
 */
const chronoParsers: Record<string, { casual: chrono.Chrono }> = {
  en: chrono.en,
  de: chrono.de,
  es: chrono.es,
  fr: chrono.fr,
  it: chrono.it,
  ja: chrono.ja,
  nl: chrono.nl,
  pt: chrono.pt,
  ru: chrono.ru,
  sv: chrono.sv,
  uk: chrono.uk,
  zh: chrono.zh,
  'zh-Hant': chrono.zh,
};

const localeDateAffixes: Record<string, { leading: string[]; trailing: string[] }> = {
  en: { leading: ['by', 'due', 'on', 'before', 'until', 'til', 'till', 'for'], trailing: [] },
  de: { leading: ['bis', 'am', 'an', 'vor'], trailing: [] },
  es: { leading: ['para', 'el', 'antes de', 'antes del', 'antes de la'], trailing: [] },
  fr: { leading: ['pour', 'le', 'avant', 'avant le'], trailing: [] },
  it: { leading: ['per', 'entro', 'il'], trailing: [] },
  ja: { leading: [], trailing: ['までに', 'まで', 'に'] },
  nl: { leading: ['voor', 'vóór', 'op', 'tegen'], trailing: [] },
  pt: { leading: ['para', 'até', 'ate', 'em'], trailing: [] },
  ru: { leading: ['к', 'до', 'на'], trailing: [] },
  sv: { leading: ['före', 'fore', 'senast', 'på', 'pa', 'till'], trailing: [] },
  uk: { leading: ['до', 'на'], trailing: [] },
  zh: { leading: ['在'], trailing: ['之前', '以前', '截止'] },
  'zh-Hant': { leading: ['在'], trailing: ['之前', '以前', '截止'] },
};

function getChronoInstance(locale: string): chrono.Chrono {
  // Exact match first, then language prefix (e.g. "en-US" -> "en")
  const langPrefix = locale.split('-')[0] ?? locale;
  const entry = chronoParsers[locale] ?? chronoParsers[langPrefix];
  return entry?.casual ?? chrono.en.casual;
}

function resolveHeuristicLocale(locale: string): string {
  const langPrefix = locale.split('-')[0] ?? locale;
  if (localeDateAffixes[locale]) return locale;
  if (localeDateAffixes[langPrefix]) return langPrefix;
  return 'en';
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function affixRegexFragment(affixes: readonly string[]): string | null {
  if (affixes.length === 0) return null;
  return affixes
    .slice()
    .sort((a, b) => b.length - a.length)
    .map((affix) => escapeRegex(affix).replace(/\s+/g, '\\s+'))
    .join('|');
}

function getLocaleDateAffixes(locale: string): { leading: string[]; trailing: string[] } {
  const langPrefix = locale.split('-')[0] ?? locale;
  return localeDateAffixes[locale] ?? localeDateAffixes[langPrefix] ?? { leading: [], trailing: [] };
}

function supportsCompactLeadingAffixes(locale: string): boolean {
  return locale === 'zh' || locale === 'zh-Hant' || locale.startsWith('zh-');
}

function isInlineCollisionProneLocale(locale: string): boolean {
  return (
    locale === 'ja' ||
    locale.startsWith('ja-') ||
    locale === 'zh' ||
    locale === 'zh-Hant' ||
    locale.startsWith('zh-')
  );
}

function normalizeCleanTitle(value: string): string {
  return value
    .replace(/\s+([,.;!?])/g, '$1')
    .replace(/([([{])\s+/g, '$1')
    .replace(/\s+([)\]}])/g, '$1')
    .replace(
      /([\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}])\s+([\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}])/gu,
      '$1$2',
    )
    .replace(/\s{2,}/g, ' ')
    .trim();
}

function hasMeaningfulTitleContent(value: string): boolean {
  return value.replace(/[\p{P}\p{Z}]/gu, '').length > 0;
}

function hasRelativePeriodSignal(result: chrono.ParsedResult, locale: string): boolean {
  if (result.tags().has('result/relativeDate')) return true;
  if (locale === 'en') {
    return /\b(?:this|current)\s+(?:month|year)\b/i.test(result.text);
  }
  return false;
}

function hasExplicitDateSignal(result: chrono.ParsedResult, locale: string): boolean {
  return (
    result.start.isCertain('day') ||
    result.start.isCertain('weekday') ||
    hasRelativePeriodSignal(result, locale)
  );
}

function isWeekdayOnlyResult(result: chrono.ParsedResult): boolean {
  return (
    result.start.isCertain('weekday') &&
    !result.start.isCertain('day') &&
    !result.start.isCertain('month') &&
    !result.start.isCertain('year')
  );
}

function isCjkCharacter(value: string): boolean {
  return /^[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]$/u.test(value);
}

function isHanCharacter(value: string): boolean {
  return /^[\p{Script=Han}]$/u.test(value);
}

function looksLikeTitleContinuation(value: string): boolean {
  return (
    /^(?:\s+|[._-])[\p{L}\p{N}_-]/u.test(value) ||
    /^[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{L}\p{N}]/u.test(value)
  );
}

/** Remove the matched date phrase from the title and normalize spacing. */
function buildCleanTitle(original: string, matchStart: number, matchEnd: number): string {
  const beforeMatch = original.slice(0, matchStart);
  const afterMatch = original.slice(matchEnd);
  return normalizeCleanTitle(beforeMatch + ' ' + afterMatch);
}

/**
 * Extract a date from natural-language text in the given locale.
 *
 * @param text - The raw task title (e.g. "finish paper by friday")
 * @param locale - App locale code (e.g. "en", "zh", "fr")
 * @param referenceDate - The "now" reference for relative dates
 * @returns A ParseResult if a date was found, or null otherwise
 */
export function parseDateFromText(
  text: string,
  locale: string,
  referenceDate: Date,
): ParseResult | null {
  if (!text.trim()) return null;

  const heuristicLocale = resolveHeuristicLocale(locale);
  const instance = getChronoInstance(locale);
  const results = instance.parse(text, referenceDate, { forwardDate: true });
  if (results.length === 0) return null;

  const { leading, trailing } = getLocaleDateAffixes(heuristicLocale);
  const explicitResults = results.filter((result) => hasExplicitDateSignal(result, heuristicLocale));
  if (explicitResults.length === 0) return null;

  for (const result of explicitResults) {
    const date = result.date();

    // Determine the full matched span including any leading filler
    let matchStart = result.index;
    let matchEnd = result.index + result.text.length;

    const beforeMatch = text.slice(0, matchStart);
    const leadingFragment = affixRegexFragment(leading);
    if (leadingFragment) {
      const leadingPattern = supportsCompactLeadingAffixes(heuristicLocale)
        ? new RegExp(`(${leadingFragment})\\s*$`, 'iu')
        : new RegExp(`(?:^|\\s)(${leadingFragment})\\s*$`, 'iu');
      const leadingMatch = beforeMatch.match(leadingPattern);
      if (leadingMatch) {
        matchStart = beforeMatch.length - leadingMatch[0].length;
      }
    }

    const afterMatch = text.slice(matchEnd);
    const trailingFragment = affixRegexFragment(trailing);
    if (trailingFragment) {
      const trailingMatch = afterMatch.match(new RegExp(`^\\s*(${trailingFragment})`, 'iu'));
      if (trailingMatch) {
        matchEnd += trailingMatch[0].length;
      }
    }

    const expandedLeadingAffix = matchStart !== result.index;
    const expandedTrailingAffix = matchEnd !== result.index + result.text.length;

    const weekdayContinuationCollision =
      isWeekdayOnlyResult(result) &&
      looksLikeTitleContinuation(text.slice(result.index + result.text.length));
    if (weekdayContinuationCollision) continue;

    const rawMatchStart = result.index;
    const rawMatchEnd = result.index + result.text.length;
    const inlineCollision =
      isInlineCollisionProneLocale(heuristicLocale) &&
      !expandedLeadingAffix &&
      !expandedTrailingAffix &&
      rawMatchStart > 0 &&
      rawMatchEnd < text.length &&
      isCjkCharacter(text.charAt(rawMatchStart - 1) ?? '') &&
      isCjkCharacter(text.charAt(rawMatchEnd) ?? '');
    const japanesePrefixCompoundCollision =
      heuristicLocale === 'ja' &&
      !expandedLeadingAffix &&
      !expandedTrailingAffix &&
      rawMatchStart === 0 &&
      rawMatchEnd < text.length &&
      isHanCharacter(text.charAt(rawMatchEnd) ?? '');
    if (inlineCollision || japanesePrefixCompoundCollision) continue;

    const matchText = text.slice(matchStart, matchEnd).trim();
    const cleanTitle = buildCleanTitle(text, matchStart, matchEnd);

    // Don't return a result if removing the date leaves an empty title
    if (!cleanTitle || !hasMeaningfulTitleContent(cleanTitle)) continue;

    return { date, cleanTitle, matchedText: matchText };
  }

  return null;
}
