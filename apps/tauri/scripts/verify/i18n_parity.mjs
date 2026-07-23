#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const localesDir = path.join(root, 'app/src/locales');
const EN_FILE = 'en.json';
const REGISTRY_FILE = path.join(localesDir, 'registry.ts');
const INVARIANT_FILE = path.join(localesDir, '_invariant.json');
const STRICT_PARITY_FILE = path.join(localesDir, 'strict-parity.json');
const TAURI_BUILD_FILE = path.join(root, 'app/src-tauri/build.rs');

// Strict-parity locales are the first-class shipping catalogs that must stay
// complete. The default set is data-owned by app/src/locales/strict-parity.json
// so future first-class locales are added by configuration, not verifier edits.
const STRICT_PARITY_LOCALES = new Set([
  ...(
    process.env.I18N_STRICT_PARITY_LOCALES ??
    JSON.parse(fs.readFileSync(STRICT_PARITY_FILE, 'utf8')).join(',')
  )
    .split(',')
    .map((code) => code.trim())
    .filter(Boolean)
    .map((code) => `${code.replace(/\.json$/, '')}.json`),
  EN_FILE,
]);
STRICT_PARITY_LOCALES.add(EN_FILE);

// Soft-parity locales intentionally allow English fallback at runtime
// (see app/src/locales/registry.ts). The verifier therefore reports
// missing keys as warnings by default while still hard-failing registry,
// switch, extra-key, and strict-locale drift. Set a tighter threshold
// in CI/local audits when intentionally chasing translation completion:
//   I18N_SOFT_PARITY_MAX_MISSING_RATIO=0.01 npm run verify:i18n
//
// Stair-step plan toward strict parity (#3413):
//   * Phase 1: 0.44 — locks the current floor where the broad soft-parity
//     locale cohort sits at 56.3% coverage (43.73% missing). A small epsilon
//     above 0.4373 prevents false negatives while guaranteeing no further
//     regression. Higher-coverage locales clear it with headroom.
//   * Phase 2 (after the next translation refresh): 0.30. Forces every
//     soft-parity locale to ≥70% coverage.
//   * Phase 3 (after a second refresh): 0.15. ≥85% everywhere.
//   * Eventually: drop the soft-parity exemption entirely and route
//     every locale through the configured strict-parity path.
//
// A brand-new locale can no longer ship at 100% missing — it must be
// at least 58% translated to land. That's intentional: the previous
// "1.0 default" silently let new locales sit at zero coverage forever.
const SOFT_PARITY_MAX_MISSING_RATIO = (() => {
  const raw = process.env.I18N_SOFT_PARITY_MAX_MISSING_RATIO;
  if (raw === undefined || raw === '') {
    return 0.44;
  }
  const parsed = Number.parseFloat(raw);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 1) {
    console.error(
      `ERROR: I18N_SOFT_PARITY_MAX_MISSING_RATIO must be a number in [0, 1]; got ${raw}`,
    );
    process.exit(2);
  }
  return parsed;
})();

let hasError = false;
let warningCount = 0;

function fail(message) {
  hasError = true;
  console.error(`ERROR: ${message}`);
}

function ok(message) {
  console.log(`OK: ${message}`);
}

function warn(message) {
  warningCount += 1;
  console.warn(`WARN: ${message}`);
}

function readJsonKeys(absPath) {
  const data = JSON.parse(fs.readFileSync(absPath, 'utf8'));
  return new Set(Object.keys(data));
}

function printList(title, items, max = 20) {
  console.error(`${title} (${items.length})`);
  for (const item of items.slice(0, max)) {
    console.error(`  - ${item}`);
  }
  if (items.length > max) {
    console.error(`  ... and ${items.length - max} more`);
  }
}

function readNativeMenuKeys() {
  if (!fs.existsSync(TAURI_BUILD_FILE)) {
    fail(`Tauri build script not found: ${TAURI_BUILD_FILE}`);
    return [];
  }
  const source = fs.readFileSync(TAURI_BUILD_FILE, 'utf8');
  return Array.from(new Set(
    Array.from(source.matchAll(/"((?:menu)\.[a-zA-Z0-9]+)"/g), (match) => match[1]),
  )).sort();
}

/**
 * Audit #2935-H3 / #3066: parse the `code: '<locale>'` entries from
 * the `localeRegistry` array plus each entry's dynamic `load` import.
 * They MUST agree with the file inventory on disk — otherwise a
 * registered locale silently returns an empty catalog at runtime, or
 * an orphan file never gets loaded.
 */
function parseRegistry(sourceText) {
  const registryRegex = /code: '([^']+)'/g;
  const codes = new Set();
  let match;
  while ((match = registryRegex.exec(sourceText))) {
    codes.add(match[1]);
  }
  return codes;
}

function parseRegistryLoaders(sourceText) {
  const entryRegex = /\{([^{}]+)\}/g;
  const loaders = new Map();
  let entryMatch;
  while ((entryMatch = entryRegex.exec(sourceText))) {
    const entry = entryMatch[1];
    const codeMatch = entry.match(/code:\s*'([^']+)'/);
    if (!codeMatch) continue;
    const loaderMatch = entry.match(/load:\s*catalog\(\(\)\s*=>\s*import\('\.\/([^']+)\.json'\)\)/);
    if (loaderMatch) {
      loaders.set(codeMatch[1], loaderMatch[1]);
    }
  }
  return loaders;
}

if (!fs.existsSync(localesDir)) {
  fail(`Locales directory not found: ${localesDir}`);
  process.exit(1);
}

const localeFiles = fs
  .readdirSync(localesDir)
  .filter((file) => file.endsWith('.json') && !file.startsWith('_') && file !== 'strict-parity.json')
  .sort();

const fileCodes = new Set(localeFiles.map((file) => file.replace(/\.json$/, '')));

if (!fs.existsSync(REGISTRY_FILE)) {
  fail(`Registry file not found: ${REGISTRY_FILE}`);
  process.exit(1);
}

const registrySource = fs.readFileSync(REGISTRY_FILE, 'utf8');
const registryCodes = parseRegistry(registrySource);
const registryLoaders = parseRegistryLoaders(registrySource);

const registryOnly = [...registryCodes].filter((c) => !fileCodes.has(c)).sort();
const filesOnly = [...fileCodes].filter((c) => !registryCodes.has(c)).sort();

if (registryOnly.length > 0) {
  fail('registry.ts lists locale codes with no matching <code>.json file');
  printList('registered without a file', registryOnly);
}
if (filesOnly.length > 0) {
  fail('locale files exist with no entry in localeRegistry');
  printList('orphan files', filesOnly);
}
if (registryOnly.length === 0 && filesOnly.length === 0) {
  ok(`registry.ts and locale files agree on ${registryCodes.size} codes`);
}

// English is loaded eagerly via static import in registry.ts (the
// fallback definition); every OTHER registered locale must have a
// matching dynamic loader in its registry entry.
const expectedLoaders = [...registryCodes].filter((c) => c !== 'en');
const loaderOnly = [...registryLoaders.keys()].filter((c) => !registryCodes.has(c)).sort();
const registryNotInLoaders = expectedLoaders.filter((c) => !registryLoaders.has(c)).sort();
const loaderImportMismatch = [];
for (const [code, importPath] of registryLoaders.entries()) {
  if (importPath !== code) {
    loaderImportMismatch.push(`${code} -> ./${importPath}.json`);
  }
}

if (registryNotInLoaders.length > 0) {
  fail('registered locales missing dynamic loaders');
  printList('registered but not loaded', registryNotInLoaders);
}
if (loaderOnly.length > 0) {
  fail('locale registry has loaders for codes not in localeRegistry');
  printList('loaded but not registered', loaderOnly);
}
if (loaderImportMismatch.length > 0) {
  fail('locale registry loader code does not match its import path');
  printList('code vs import-path mismatch', loaderImportMismatch);
}
if (
  registryNotInLoaders.length === 0 &&
  loaderOnly.length === 0 &&
  loaderImportMismatch.length === 0
) {
  ok(`locale registry loaders cover ${registryLoaders.size} non-English registered locales`);
}

if (!localeFiles.includes(EN_FILE)) {
  fail(`Missing source locale file: ${EN_FILE}`);
  process.exit(1);
}

const enKeysSet = readJsonKeys(path.join(localesDir, EN_FILE));

// _invariant.json hoists keys whose values are byte-identical across every
// locale (proper nouns, keyboard labels, schema discriminators). Each
// locale spreads `INVARIANT` into its catalog at runtime via registry.ts,
// so the parity verifier must treat those keys as present in every locale —
// even though they no longer appear in any per-locale JSON file.
const invariantKeys = fs.existsSync(INVARIANT_FILE) ? readJsonKeys(INVARIANT_FILE) : new Set();
for (const key of invariantKeys) {
  enKeysSet.add(key);
}
const enKeys = Array.from(enKeysSet);

if (enKeys.length === 0) {
  fail('No translation keys found in en.json.');
  process.exit(1);
}

ok(`Source locale ${EN_FILE} contains ${enKeys.length} keys`);

const nativeMenuKeys = readNativeMenuKeys();
const nativeMenuKeySet = new Set(nativeMenuKeys);
const softParityReferenceKeys = enKeys.filter((key) => !nativeMenuKeySet.has(key));
if (nativeMenuKeys.length === 0) {
  fail('Tauri native menu codegen must declare required menu.* locale keys');
} else {
  const missingNativeMenuKeys = nativeMenuKeys.filter((key) => !enKeysSet.has(key));
  if (missingNativeMenuKeys.length > 0) {
    fail(`${EN_FILE}: missing native menu keys required by app/src-tauri/build.rs`);
    printList(`${EN_FILE} missing native menu keys`, missingNativeMenuKeys);
  } else {
    ok(`Native menu codegen keys are present in ${EN_FILE} (${nativeMenuKeys.length} keys)`);
  }
}

for (const file of localeFiles) {
  if (file === EN_FILE) continue;

  const keys = readJsonKeys(path.join(localesDir, file));
  // INVARIANT is spread at runtime by registry.ts — count those keys as
  // present in every locale.
  for (const key of invariantKeys) keys.add(key);

  const missing = enKeys.filter((key) => !keys.has(key));
  const extra = Array.from(keys).filter((key) => !enKeysSet.has(key)).sort();
  const strictParity = STRICT_PARITY_LOCALES.has(file);
  // Native menu generation only emits locales with a complete `menu.*`
  // namespace; partial soft-locale menu tables intentionally fall back to
  // English instead of producing hybrid-language native menus. Configured
  // strict-parity locales must stay complete, but native-menu-only keys should
  // not regress the soft parity floor that tracks the React runtime catalogs.
  const softParityMissing = strictParity
    ? missing
    : missing.filter((key) => !nativeMenuKeySet.has(key));
  const deferredNativeMenuMissing = strictParity ? 0 : missing.length - softParityMissing.length;

  if (missing.length > 0) {
    if (strictParity) {
      fail(`${file}: missing translation keys compared to ${EN_FILE}`);
      printList(`${file} missing keys`, missing);
    } else {
      // Audit #3035-M7: escalate to hard fail when the missing-key
      // ratio exceeds the threshold. The runtime fallback masks
      // individual missing keys silently, so without a build gate a
      // locale can drift catastrophically before anyone notices.
      const ratio = softParityMissing.length / softParityReferenceKeys.length;
      const ratioPct = (ratio * 100).toFixed(2);
      const thresholdPct = (SOFT_PARITY_MAX_MISSING_RATIO * 100).toFixed(2);
      if (ratio > SOFT_PARITY_MAX_MISSING_RATIO) {
        fail(
          `${file}: missing ${softParityMissing.length} of ${softParityReferenceKeys.length} ` +
            `soft-parity keys ` +
            `(${ratioPct}%, exceeds ${thresholdPct}% threshold). ` +
            `${deferredNativeMenuMissing} native menu key(s) are excluded because native menu ` +
            `codegen falls back for incomplete soft locales. ` +
            `Translate the missing keys or set I18N_SOFT_PARITY_MAX_MISSING_RATIO ` +
            `if onboarding a brand-new locale.`,
        );
        printList(`${file} missing soft-parity keys`, softParityMissing);
      } else {
        warn(
          `${file}: missing ${softParityMissing.length} soft-parity key(s) ` +
            `(${ratioPct}%) — under ${thresholdPct}% threshold; ` +
            `${deferredNativeMenuMissing} native menu key(s) deferred to English fallback`,
        );
      }
    }
  }

  if (extra.length > 0) {
    fail(`${file}: contains unknown keys not present in ${EN_FILE}`);
    printList(`${file} extra keys`, extra);
  }

  if (missing.length === 0 && extra.length === 0) {
    ok(`${file}: key parity is complete (${keys.size} keys)`);
  } else if (!strictParity && extra.length === 0) {
    const coverage =
      ((softParityReferenceKeys.length - softParityMissing.length) /
        softParityReferenceKeys.length) *
      100;
    ok(
      `${file}: soft parity mode ` +
        `(${softParityReferenceKeys.length - softParityMissing.length}/` +
        `${softParityReferenceKeys.length} comparable keys, ${coverage.toFixed(1)}% coverage)`,
    );
  }
}

// Audit #2940-L1: scan TS/TSX for any string literal that looks like
// a translation key, intersect with `en.json` keys, and warn on every
// `en.json` key with zero matches. The audit's frontend pass found 393
// keys that LOOK orphaned to a naive scan but are actually referenced
// via dynamic `titleKey` / `labelKey` lookups (e.g.
// `t(item.titleKey)` where `item.titleKey` is a runtime string). This
// scan deliberately ignores the literal-vs-runtime distinction —
// it only cares whether the key string appears ANYWHERE in the
// source tree. If a key is truly orphaned, this surfaces it; if it's
// referenced indirectly via a literal-string lookup table, the scan
// finds the literal and the key is considered live.
//
// Reported as a WARN, not a hard error, because dynamic-key
// construction (`t(\`task.${status}.label\`)`) cannot be statically
// resolved by this scanner — a reported "orphan" may still be live
// at runtime. Operators triage manually before deletion.
const appSrcDir = path.join(root, 'app/src');
const referencedKeys = collectReferencedKeysFromTree(appSrcDir);
const truelyOrphaned = enKeys.filter((key) => !referencedKeys.has(key));
if (truelyOrphaned.length > 0) {
  warn(
    `${truelyOrphaned.length} en.json key(s) appear unreferenced in app/src/**/*.{ts,tsx} ` +
      '(may be dynamic-lookup via titleKey/labelKey patterns; verify before deletion)',
  );
  if (truelyOrphaned.length <= 50) {
    printList('apparently unreferenced en.json keys', truelyOrphaned, 50);
  }
}

if (hasError) {
  process.exit(1);
}

if (warningCount > 0) {
  console.log(
    `i18n parity verification passed with ${warningCount} warning(s) in soft-parity locales.`,
  );
} else {
  console.log('i18n parity verification passed.');
}

/**
 * Recursively walk a directory and concatenate every `.ts` / `.tsx`
 * file's content. Ignores `node_modules`, `.git`, build outputs.
 * Returns a single string — callers use a regex to extract any
 * substring that COULD be a translation key.
 */
function readTsTreeText(dir) {
  let buffer = '';
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      buffer += readTsTreeText(full);
    } else if (entry.isFile() && /\.(ts|tsx)$/.test(entry.name)) {
      buffer += fs.readFileSync(full, 'utf8');
      buffer += '\n';
    }
  }
  return buffer;
}

/** Extract every string-literal substring from the source tree. We
 *  match any sequence of word-characters and dots that LOOKS like a
 *  translation key (`foo.bar`, `nav.today.desc`). Returns the set of
 *  unique candidates. */
function collectReferencedKeysFromTree(dir) {
  const text = readTsTreeText(dir);
  const candidates = new Set();
  const re = /[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_]+)+/g;
  let match;
  while ((match = re.exec(text))) {
    candidates.add(match[0]);
  }
  return candidates;
}
