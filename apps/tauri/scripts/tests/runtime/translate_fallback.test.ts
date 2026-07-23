import assert from 'node:assert/strict';
import test from 'node:test';

import { formatPluralTranslation, translate } from '../../../app/src/locales';
import { fallbackTranslations } from '../../../app/src/locales/registry';

// Pick a key that is known to exist in `en.ts` (which backs
// `fallbackTranslations`). `common.save` is a safe anchor — it's one
// of the earliest keys defined in the English locale.
const KNOWN_KEY = 'common.save' as const;

type TranslationKey = Parameters<typeof translate>[1];

const TASK_COUNT_KEYS = {
  zero: 'common.taskCount.zero',
  one: 'common.taskCount.one',
  two: 'common.taskCount.two',
  few: 'common.taskCount.few',
  many: 'common.taskCount.many',
  other: 'common.taskCount.other',
} as const;

test('translate returns the locale string when the locale table is loaded and has the key', () => {
  // English locale is always present in `localeMap` (eagerly imported).
  // `translate('en', KNOWN_KEY)` must return the English translation,
  // not the key literal or a fallback chain miss.
  const result = translate('en', KNOWN_KEY);
  assert.ok(
    result && result !== KNOWN_KEY,
    `expected 'en' translation to resolve, got: ${JSON.stringify(result)}`,
  );
  assert.equal(result, fallbackTranslations[KNOWN_KEY]);
});

test('translate falls back to English when the locale table is NOT loaded', () => {
  // Non-English locales ship as async chunks; before `loadLocale()`
  // resolves, `localeMap.get('zh')` returns undefined. The translate
  // function must walk to `fallbackTranslations` (English) in that
  // window, not the key literal. Without async loading invoked, this
  // test exercises the not-loaded-yet branch.
  const englishFallback = fallbackTranslations[KNOWN_KEY];
  const result = translate('zh', KNOWN_KEY);
  assert.equal(
    result,
    englishFallback,
    'un-loaded locale must fall back to English, not the key literal',
  );
});

test('translate returns the key literal when English fallback also lacks the key', () => {
  // Regression signal: when a developer references a key that hasn't
  // been added to `en.ts` yet, the cascade's third layer should return
  // the raw key string. This makes the bug visible in the UI instead
  // of failing silently with an empty string / `undefined`.
  const nonexistent = 'nonexistent.key.should.never.exist' as TranslationKey;
  const result = translate('en', nonexistent);
  assert.equal(result, nonexistent);
});

test('translate falls back to English for an unknown locale code', () => {
  // An unknown locale code (user manually poked the preferences DB,
  // sync envelope from a peer running an unreleased build) must not
  // crash or return the raw key. English fallback is the defensible
  // degraded state.
  const englishFallback = fallbackTranslations[KNOWN_KEY];
  const result = translate('xx-nonexistent', KNOWN_KEY);
  assert.equal(result, englishFallback);
});

test('translate returns the key literal when unknown locale AND unknown key', () => {
  // Compound degradation: the caller passed an invalid locale AND a
  // key that never existed. The cascade bottoms out at the key
  // literal rather than throwing.
  const nonexistent = 'another.fabricated.missing.key' as TranslationKey;
  const result = translate('xx-nonexistent', nonexistent);
  assert.equal(result, nonexistent);
});

test('formatPluralTranslation uses English plural rules when it falls back to English templates', () => {
  assert.equal(formatPluralTranslation('fr', 0, TASK_COUNT_KEYS), '0 tasks');
  assert.equal(formatPluralTranslation('fr', 1, TASK_COUNT_KEYS), '1 task');
});
