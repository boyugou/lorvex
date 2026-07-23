#!/usr/bin/env node
/**
 * Codegen: derive `TranslationKey` (literal union of all keys in en.json
 * + _invariant.json) and write `app/src/locales/types.generated.ts`.
 *
 * Run via:    node scripts/generate/locale_types.mjs
 * Wired into: scripts/generate/repo_facts.mjs (regenerated alongside it).
 *
 * Why a literal union and not `keyof typeof en`?
 *   The previous setup imported the en.ts module to derive
 *   `keyof typeof en`. Now en is a JSON file: TS can `import` JSON
 *   under `resolveJsonModule`, but the inferred type would be
 *   `Record<string, string>` unless we either:
 *     (a) use `import en from './en.json' with { type: 'json' }` plus
 *         a const-assertion shim, or
 *     (b) emit a literal-union type from the JSON keyset directly.
 *   (b) is simpler, faster for the type-checker on a 1.8k-key catalog,
 *   and matches how every mainstream i18n library does it.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..', '..');
const localesDir = path.join(repoRoot, 'app', 'src', 'locales');

function readJson(name) {
  return JSON.parse(fs.readFileSync(path.join(localesDir, name), 'utf8'));
}

const en = readJson('en.json');
const invariant = readJson('_invariant.json');
const checkMode = process.argv.includes('--check');

// Union the two — en.json already contains the invariant keys (we
// kept en as the master, INVARIANT-included); the explicit union here
// is defensive in case that contract slips.
const keys = Array.from(new Set([...Object.keys(en), ...Object.keys(invariant)])).sort();

const out = path.join(localesDir, 'types.generated.ts');
const output = buildLocaleTypesOutput(keys);

if (checkMode) {
  const current = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : '';
  if (current !== output) {
    console.error(
      `ERROR: ${path.relative(repoRoot, out)} types.generated.ts is stale; run npm run codegen:locale-types`,
    );
    process.exit(1);
  }
  console.log(`OK: ${path.relative(repoRoot, out)} is fresh (${keys.length} keys)`);
} else {
  fs.writeFileSync(out, output, 'utf8');
  console.log(`OK: wrote ${path.relative(repoRoot, out)} (${keys.length} keys)`);
}

function buildLocaleTypesOutput(localeKeys) {
  const lines = [];
  lines.push('// AUTO-GENERATED FILE — DO NOT EDIT BY HAND');
  lines.push('// Regenerate via: node scripts/generate/locale_types.mjs');
  lines.push('// Source: app/src/locales/en.json + _invariant.json');
  lines.push('');
  lines.push('export type TranslationKey =');
  localeKeys.forEach((key, idx) => {
    const escaped = key.replaceAll("'", "\\'");
    const suffix = idx === localeKeys.length - 1 ? ';' : '';
    lines.push(`  | '${escaped}'${suffix}`);
  });
  lines.push('');
  return lines.join('\n');
}
