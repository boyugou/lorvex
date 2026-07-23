import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('locales keep catalogs separate from registry and runtime logic', () => {
  const indexSource = fs.readFileSync(path.join(repoRoot, 'app/src/locales/index.ts'), 'utf8');
  const registrySource = fs.readFileSync(path.join(repoRoot, 'app/src/locales/registry.ts'), 'utf8');
  const runtimeSource = fs.readFileSync(path.join(repoRoot, 'app/src/locales/runtime.ts'), 'utf8');

  assert.match(
    indexSource,
    /export \{(?=[\s\S]*localeRegistry)(?=[\s\S]*normalizeLocaleCode)[\s\S]*} from '\.\/registry';/m,
    'locales index should re-export registry-owned locale catalog data',
  );
  assert.match(
    indexSource,
    /export \{[\s\S]*detectSystemLocale[\s\S]*resolveLocalePreference[\s\S]*translate[\s\S]*} from '\.\/runtime';/m,
    'locales index should re-export runtime-owned locale helpers',
  );
  assert.doesNotMatch(
    indexSource,
    /export const localeRegistry:|export function translate\(|export function detectSystemLocale\(/,
    'locales index should stay a barrel after extraction',
  );

  assert.match(
    registrySource,
    /export const localeRegistry\s*=\s*\[[\s\S]*?\]\s+as const satisfies readonly LocaleDefinition\[];/,
  );
  assert.match(registrySource, /export const localeMap = new Map/);
  assert.match(registrySource, /export const fallbackTranslations:/);
  assert.doesNotMatch(
    registrySource,
    /export function detectSystemLocale\(|export function resolveLocalePreference\(/,
    'locale registry should not own runtime preference resolution after extraction',
  );

  assert.match(runtimeSource, /export function translate\(/);
  assert.match(runtimeSource, /export function isValidLocale\(/);
  assert.match(runtimeSource, /export function detectSystemLocale\(/);
  assert.match(runtimeSource, /export function resolveLocalePreference\(/);
  assert.doesNotMatch(
    runtimeSource,
    /export const localeRegistry:|import en, \{ type TranslationKey \} from '\.\/en';/,
    'locale runtime should consume registry data instead of owning locale catalogs directly',
  );
});
