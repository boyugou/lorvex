import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

function readQuotedValuesFromTsArray(source, constName) {
  const pattern = new RegExp(`export const ${constName} = \\[([\\s\\S]*?)\\] as const;`);
  const match = source.match(pattern);
  assert.ok(match, `Expected ${constName} array in source`);
  return Array.from(match[1].matchAll(/'([^']+)'/g), (item) => item[1]);
}

function readLocaleRegistryCodes(source) {
  const registryMatch = source.match(/export const localeRegistry\s*=\s*\[([\s\S]*?)\]\s+as const satisfies readonly LocaleDefinition\[];/);
  assert.ok(registryMatch, 'Expected localeRegistry array in app locale source');
  return Array.from(registryMatch[1].matchAll(/code:\s*'([^']+)'/g), (item) => item[1]);
}

test('app locale registry stays aligned with shared supported locales', () => {
  const sharedTypes = fs.readFileSync(path.join(repoRoot, 'shared/src/types.ts'), 'utf8');
  const appLocales = fs.readFileSync(path.join(repoRoot, 'app/src/locales/registry.ts'), 'utf8');

  const sharedLocales = readQuotedValuesFromTsArray(sharedTypes, 'SUPPORTED_LOCALES');
  const appLocaleCodes = readLocaleRegistryCodes(appLocales);

  assert.deepEqual(
    appLocaleCodes,
    sharedLocales,
    'app localeRegistry codes should match shared SUPPORTED_LOCALES exactly',
  );
});

test('generated locale TranslationKey union has a verify-only freshness gate', () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
  const localeTypesGenerator = fs.readFileSync(
    path.join(repoRoot, 'scripts/generate/locale_types.mjs'),
    'utf8',
  );
  const verificationManifest = fs.readFileSync(
    path.join(repoRoot, 'scripts/verify/verification_manifest.mjs'),
    'utf8',
  );

  assert.equal(
    packageJson.scripts['verify:locale-types'],
    'node scripts/generate/locale_types.mjs --check',
    'package.json should expose a check-mode locale type freshness gate',
  );
  assert.match(localeTypesGenerator, /process\.argv\.includes\('--check'\)/);
  assert.match(localeTypesGenerator, /types\.generated\.ts is stale/);
  assert.match(
    verificationManifest,
    /npmScript\('verify:locale-types'\)/,
    'repo-governance should run the generated locale type freshness gate',
  );
});

test('native menu i18n is generated from canonical JSON locale catalogs', () => {
  const buildSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/build.rs'), 'utf8');
  const cargoToml = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/Cargo.toml'), 'utf8');
  const menuI18nSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/menu_i18n.rs'), 'utf8');
  const appMenuSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/desktop_shell/app_menu.rs'),
    'utf8',
  );
  const i18nParitySource = fs.readFileSync(path.join(repoRoot, 'scripts/verify/i18n_parity.mjs'), 'utf8');
  const strictParityLocales = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'app/src/locales/strict-parity.json'), 'utf8'),
  );
  assert.ok(
    Array.isArray(strictParityLocales) && strictParityLocales.length >= 1,
    'strict-parity.json should define the first-class locale catalog set',
  );
  const strictParityCatalogs = strictParityLocales.map((localeCode) => [
    localeCode,
    JSON.parse(fs.readFileSync(path.join(repoRoot, `app/src/locales/${localeCode}.json`), 'utf8')),
  ]);

  const menuKeys = Array.from(new Set(
    Array.from(buildSource.matchAll(/"((?:menu)\.[a-zA-Z0-9]+)"/g), (match) => match[1]),
  )).sort();
  assert.ok(menuKeys.length >= 30, 'Tauri build script should own the native menu key list');
  for (const key of menuKeys) {
    for (const [localeCode, catalog] of strictParityCatalogs) {
      assert.equal(typeof catalog[key], 'string', `${localeCode}.json must define ${key}`);
    }
  }

  assert.match(cargoToml, /\[build-dependencies\][\s\S]*serde_json = "1"/);
  assert.match(buildSource, /fn emit_menu_i18n\(\)/);
  assert.match(buildSource, /menu_i18n\.generated\.rs/);
  assert.match(buildSource, /parse_locale_registry_codes/);
  assert.match(buildSource, /parse_strict_parity_locale_codes/);
  assert.match(buildSource, /strict-parity\.json must define at least one native menu parity locale/);
  assert.match(buildSource, /because it is listed in strict-parity\.json/);
  assert.match(menuI18nSource, /include!\(concat!\(env!\("OUT_DIR"\), "\/menu_i18n\.generated\.rs"\)\);/);
  assert.doesNotMatch(menuI18nSource, /\("en",\s*MenuKey::\w+\)\s*=>/);
  assert.doesNotMatch(menuI18nSource, /\("zh",\s*MenuKey::\w+\)\s*=>/);
  assert.doesNotMatch(buildSource, /zh\.json must define every native menu key/);
  assert.doesNotMatch(menuI18nSource, /TODO\(#3328 follow-up\)/);
  assert.match(appMenuSource, /SubmenuBuilder::new\(app, t\(MenuKey::FileMenu\)\)/);
  assert.match(appMenuSource, /SubmenuBuilder::new\(app, t\(MenuKey::HelpMenu\)\)/);
  assert.match(i18nParitySource, /readNativeMenuKeys/);
  assert.match(i18nParitySource, /Native menu codegen keys are present/);
  assert.match(i18nParitySource, /softParityReferenceKeys/);
  assert.match(i18nParitySource, /native menu key\(s\) deferred to English fallback/);
  assert.doesNotMatch(
    i18nParitySource,
    /en\/zh|English\/Chinese|two-locale|two locale|two-language|two language/,
    'i18n parity verifier should describe strict locales as data-configured, not as a fixed English/Chinese pair',
  );
});

test('locale contract verifiers parse canonical JSON catalogs without legacy facades', () => {
  const helperSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/lib/ui_wiring_contract_support.mjs'),
    'utf8',
  );
  const verifierSources = [
    'scripts/verify/ui_wiring.mjs',
    'scripts/verify/sync_filesystem_bridge_cursor_contract.mjs',
    'scripts/verify/popover_settings_feedback_contract.mjs',
  ].map((relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'));
  const legacyRendererName = ['synthesize', 'Locale', 'Source', 'From', 'Json'].join('');
  const legacyRendererPattern = new RegExp(legacyRendererName);
  const legacyKeyValueFacadePattern = new RegExp(['`', "'<key>'", ': ', "'<value>'", '`'].join(''));

  assert.match(helperSource, /export function readLocaleCatalog\(/);
  assert.match(helperSource, /export function missingLocaleCatalogKeys\(/);
  assert.doesNotMatch(helperSource, legacyRendererPattern);
  assert.doesNotMatch(helperSource, /old `app\/src\/locales\/en\.ts`/);
  for (const source of verifierSources) {
    assert.doesNotMatch(source, legacyRendererPattern);
    assert.doesNotMatch(source, legacyKeyValueFacadePattern);
    assert.doesNotMatch(source, /new RegExp\(`'\$\{escapeRegex\(key\)\}':\\\\s\*`\)/);
  }
});

test('UI and notifications share the same language preference resolver semantics', () => {
  const localeIndexSource = fs.readFileSync(path.join(repoRoot, 'app/src/locales/index.ts'), 'utf8');
  const localeRegistrySource = fs.readFileSync(path.join(repoRoot, 'app/src/locales/registry.ts'), 'utf8');
  const localeRuntimeSource = fs.readFileSync(path.join(repoRoot, 'app/src/locales/runtime.ts'), 'utf8');
  const i18nSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/i18n.tsx'), 'utf8');
  const notificationsSource = readTypeScriptSources('app/src/lib/notifications');

  assert.match(
    localeRuntimeSource,
    /export function resolveLocalePreference\(raw: string \| null\): \{ locale: Locale; usingSystemLocale: boolean \} \{/,
    'app locales should expose a shared language preference resolver for all runtime consumers',
  );
  assert.match(
    localeIndexSource,
    /export \{[\s\S]*resolveLocalePreference[\s\S]*translate[\s\S]*} from '\.\/runtime';/m,
    'locales index should remain a thin barrel over runtime helpers',
  );
  assert.match(
    localeIndexSource,
    /export \{[\s\S]*localeRegistry[\s\S]*} from '\.\/registry';/m,
    'locales index should remain a thin barrel over locale registry data',
  );
  assert.match(
    localeRegistrySource,
    /export const localeRegistry\s*=\s*\[[\s\S]*?\]\s+as const satisfies readonly LocaleDefinition\[];/,
    'locale registry should own the canonical locale catalog list',
  );
  assert.match(
    i18nSource,
    /const resolved = resolveLocalePreference\(raw\);[\s\S]*?resolved\.locale[\s\S]*?setUsingSystemLocale\(resolved\.usingSystemLocale\);/s,
    'I18nProvider should derive locale/bootstrap mode from the shared resolver instead of inlining its own fallback rules',
  );
  assert.match(
    notificationsSource,
    /resolveLocalePreference\([\s\S]*?\)\.locale/,
    'notification polling should derive locale from the same shared resolver the UI uses',
  );
  assert.doesNotMatch(
    notificationsSource,
    /function parseLocalePreference\(raw: string \| null\): string \{/,
    'notifications.ts should not keep a divergent local language preference parser',
  );
});
