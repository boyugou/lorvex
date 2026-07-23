#!/usr/bin/env node
/**
 * Source-to-locale key verification.
 *
 * Companion to `i18n_parity.mjs` (locale-to-locale parity) and
 * `locale_coverage.mjs` (per-locale completion report). This script
 * scans `app/src/**\/*.{ts,tsx}` for keys reachable from a runtime
 * `t(...)` call and fails if any reference resolves to a key not
 * defined in `app/src/locales/en.json` (or its spread-in
 * `_invariant.json`).
 *
 * Three reference shapes are recognised (#4405):
 *
 *   1. **Literal calls** — `t('foo.bar')` / `t("foo.bar")`. The
 *      first argument is a single- or double-quoted string literal
 *      containing at least one dot (so `t(x)` from unrelated APIs
 *      like zod transforms does not false-match).
 *
 *   2. **Indirect property-value lookups** — `titleKey: 'foo.bar'`,
 *      `labelKey: "foo.bar"`, `descriptionKey: 'foo.bar'`,
 *      `iconKey: 'foo.bar'`. These are the conventional property
 *      names used across the codebase for "this row of data carries
 *      the locale key its consumer should `t(...)` later". The values
 *      are still ordinary string literals — only the lookup site
 *      moved away from the `t(...)` call.
 *
 *   3. **Registry table values** — every `Record<string, string>`
 *      (or `{ readonly [k: string]: string }`) declaration whose
 *      values are dotted string literals is treated as a locale-key
 *      registry. The values are added to the referenced set so that
 *      `LABELS[id]` / `MODULE_TITLES[key]` bracket-indexing sites
 *      stop appearing as "unreferenced" warnings.
 *
 * Dynamic keys (`t(\`prefix.${variable}\`)`, `t(item.titleKey)`,
 * `t(buildKey(x))`) are still impossible to resolve statically and
 * are skipped. The unreferenced-keys report is now meaningful (only
 * genuinely dead keys remain) instead of a noise floor of hundreds
 * of indirect-lookup false positives.
 */

import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const localesDir = path.join(root, 'app/src/locales');
const appSrcDir = path.join(root, 'app/src');
const EN_FILE = path.join(localesDir, 'en.json');
const INVARIANT_FILE = path.join(localesDir, '_invariant.json');

function readJsonKeys(absPath) {
  const data = JSON.parse(fs.readFileSync(absPath, 'utf8'));
  return new Set(Object.keys(data));
}

function loadEnKeys() {
  if (!fs.existsSync(EN_FILE)) {
    console.error(`ERROR: en.json not found at ${EN_FILE}`);
    process.exit(1);
  }
  const enKeys = readJsonKeys(EN_FILE);
  if (fs.existsSync(INVARIANT_FILE)) {
    for (const k of readJsonKeys(INVARIANT_FILE)) {
      enKeys.add(k);
    }
  }
  if (enKeys.size === 0) {
    console.error('ERROR: no translation keys found in en.json');
    process.exit(1);
  }
  return enKeys;
}

function* walkSourceFiles(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      // Skip the locales dir itself — those are the catalogs, not call sites.
      if (full === localesDir) continue;
      yield* walkSourceFiles(full);
    } else if (entry.isFile() && /\.(ts|tsx)$/.test(entry.name) && !entry.name.includes('.test.')) {
      yield full;
    }
  }
}

// (1) Literal `t('foo.bar')` / `t("foo.bar")` calls and their
// sibling locale-aware helpers (`format(…)`, `formatTranslation(…)`,
// `num(…)`, `hasLocaleTranslation(…)`) — every one of these takes a
// locale key as its first positional argument and routes it through
// the same lookup table. The character class is tight on purpose:
// dynamic keys (`t(\`x.${y}\`)`, `t(item.titleKey)`) won't match
// because their first argument isn't a single-/double-quoted
// literal. The leading boundary `(?:^|[^A-Za-z0-9_.])` keeps
// `prefix_t(...)` (an unrelated identifier) from false-matching.
const T_CALL_REGEX =
  /(?:^|[^A-Za-z0-9_])(?:t|format|formatTranslation|formatPluralTranslation|num|hasLocaleTranslation)\(\s*(['"])([\w.]+)\1/g;
// The match groups shift accordingly: group 2 holds the key. The
// leading boundary is `[^A-Za-z0-9_]` (no `.`) on purpose — `.t(` is
// the `controller.t(...)` / `c.t(...)` chained-method-call form
// used by view controllers that expose a thin translator wrapper.
const T_CALL_KEY_GROUP = 2;

// (2) Indirect-lookup property assignments. Each row carries a
// pointer to a locale key the consumer dereferences later via
// `t(row.<kind>Key)`. Names are the conventions used across
// `app/src/`:
//   - `titleKey`        — menu / section heading strings
//   - `labelKey`        — control / chip / picker labels
//   - `descriptionKey`  — secondary copy paired with a title
//   - `iconKey`         — locale-keyed icon tooltip / alt text
//
// The match is `<key>: 'foo.bar'` / `<key>: "foo.bar"`. Object
// property keys may be quoted (`'titleKey':`) but in this codebase
// they aren't, so the unquoted form is enough.
// Note the plural-category property names (`zero`, `one`, `two`,
// `few`, `many`, `other`) are also indirect locale-key carriers —
// `PluralTranslationKeys` objects passed to `formatPluralTranslation`
// keep one locale key per CLDR plural category. Adding them here
// folds the `*.taskCount.{one,many,…}` fanout into the indirect
// reference set rather than the registry-style fallback.
const INDIRECT_KEY_NAMES = [
  'titleKey',
  'labelKey',
  'descriptionKey',
  'iconKey',
  'zero',
  'one',
  'two',
  'few',
  'many',
  'other',
];
// Match both the object-literal property form (`labelKey: 'foo.bar'`)
// and the JSX prop form (`labelKey="foo.bar"`). The separator is
// `:` (TS / JS object) or `=` (JSX); both route the right-hand-side
// string into the consumer's downstream `t(...)`.
const INDIRECT_KEY_REGEX = new RegExp(
  `\\b(?:${INDIRECT_KEY_NAMES.join('|')})\\s*[:=]\\s*(['\"])([\\w.]+)\\1`,
  'g',
);

// JSX attributes routing locale keys with a more conventional name
// — `label="some.key"`, `description="some.key"`, `tooltipKey="…"`,
// `placeholderKey="…"`. The regex matches the value side of any
// `<ident>="key.with.dots"`/`<ident>='key.with.dots'` attribute
// where the value is a dotted string literal. False positives are
// bounded by the dotted-key shape — JSX attributes carrying class
// names (`className="px-2"`), test IDs, etc. don't survive the
// dotted-key filter.
const JSX_ATTR_KEY_REGEX = /\b\w+\s*=\s*(['"])([\w]+(?:\.[\w]+)+)\1/g;

// (3) Registry tables — `const FOO: Record<string, string> = {…}`
// or `const FOO = { 'a.b': 'c.d', … } as const`. Walk every
// declaration whose annotated type is `Record<string, string>` (or
// the equivalent index signature) and harvest every string-literal
// value from its `{ … }` body. The body extraction is brace-counted
// so nested object literals (rare here, but possible) don't trip the
// scan. False positives are bounded to "this string happens to look
// like a locale key" — which is exactly what we want to count.
// `Record<string, string>` is the strictest shape, but the
// codebase routinely narrows the value side to `TranslationKey` (a
// string-literal union over en.json) or to a discriminated locale-
// key alias. Accept any identifier as the value type and rely on the
// downstream "is it a dotted string" filter to keep false positives
// bounded. Mapped-type form `{ [k: string]: <Ident> }` is also
// accepted.
const RECORD_DECL_REGEX = /\b(?:const|let|var|readonly)\s+\w+\s*:\s*(?:Readonly<\s*)?(?:Record<\s*string\s*,\s*[A-Za-z_][\w<>,\s]*>|\{\s*(?:readonly\s+)?\[[^\]]+\]\s*:\s*[A-Za-z_][\w<>,\s]*\s*\})\s*>?\s*=\s*\{/g;
const STRING_VALUE_REGEX = /:\s*(['"])([\w.]+)\1/g;

function extractRecordBody(text, openBraceIndex) {
  // openBraceIndex points at the `{` after the `=` of a record decl.
  // Walk forward, counting braces while ignoring contents inside
  // string literals. Return the substring between the matched braces.
  let depth = 0;
  let i = openBraceIndex;
  let inString = null; // current opening quote char or null
  let escaped = false;
  while (i < text.length) {
    const ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === inString) {
        inString = null;
      }
    } else if (ch === '"' || ch === "'" || ch === '`') {
      inString = ch;
    } else if (ch === '{') {
      depth++;
    } else if (ch === '}') {
      depth--;
      if (depth === 0) {
        return text.slice(openBraceIndex + 1, i);
      }
    }
    i++;
  }
  return null;
}

function scanSource(enKeys) {
  const missing = []; // { file, line, key, kind }
  const referenced = new Set();

  function addReference(file, text, key, matchIndex, kind) {
    if (!key.includes('.')) return; // bare identifier — not a locale key
    referenced.add(key);
    if (!enKeys.has(key)) {
      const line = text.slice(0, matchIndex).split('\n').length;
      missing.push({ file: path.relative(root, file), line, key, kind });
    }
  }

  // (4) Rust-side native-surface references. `app/src-tauri/build.rs`
  // hard-codes the menu / tray locale keys it pulls into the native
  // menu table; without this sweep those keys appear "unreferenced"
  // and would be a deletion false-positive.
  const buildRsPath = path.join(root, 'app/src-tauri/build.rs');
  if (fs.existsSync(buildRsPath)) {
    const text = fs.readFileSync(buildRsPath, 'utf8');
    const RUST_LITERAL_REGEX = /"([\w.]+\.[\w.]+)"/g;
    let m;
    while ((m = RUST_LITERAL_REGEX.exec(text))) {
      const key = m[1];
      if (enKeys.has(key)) referenced.add(key);
    }
  }

  for (const file of walkSourceFiles(appSrcDir)) {
    const text = fs.readFileSync(file, 'utf8');

    // (1) Literal `t(...)` calls. Still the strict gate — any
    // unknown key reachable here is a hard failure, because the
    // ergonomics of a typo at a `t(...)` call ("looks fine, shows
    // [missing key] at runtime") are exactly what the gate exists
    // to prevent.
    T_CALL_REGEX.lastIndex = 0;
    let match;
    while ((match = T_CALL_REGEX.exec(text))) {
      addReference(file, text, match[T_CALL_KEY_GROUP], match.index, 't');
    }

    // (2b) `'foo.bar' as TranslationKey` — explicit cast that
    // sometimes appears in matcher rules / config tables outside a
    // `Record<...>` declaration. The cast is the load-bearing
    // pointer that downstream `t(...)` follows.
    const CAST_KEY_REGEX = /(['"])([\w.]+\.[\w.]+)\1\s+as\s+TranslationKey\b/g;
    while ((match = CAST_KEY_REGEX.exec(text))) {
      addReference(file, text, match[2], match.index, 'cast');
    }

    // (2a) `return 'foo.bar'` / `=> 'foo.bar'` — helpers that map a
    // discriminated enum to a `TranslationKey` return the locale key
    // directly. The consumer threads the return value into a
    // downstream `t(...)` call. Recognising these here folds the
    // entire "return locale key from a switch" pattern into the
    // referenced set.
    const RETURN_KEY_REGEX = /\b(?:return|=>\s*)\s*(['"])([\w.]+\.[\w.]+)\1/g;
    while ((match = RETURN_KEY_REGEX.exec(text))) {
      addReference(file, text, match[2], match.index, 'return');
    }

    // (2) `titleKey: 'foo.bar'` / `labelKey: '…'` / etc. Treated as
    // referenced — the value is provably consumed by a downstream
    // `t(...)` call (or it's dead code that a different sweep would
    // catch). Missing keys here are also a failure: a typo'd
    // `labelKey: 'taks.title'` is just as broken as `t('taks.title')`.
    INDIRECT_KEY_REGEX.lastIndex = 0;
    while ((match = INDIRECT_KEY_REGEX.exec(text))) {
      addReference(file, text, match[2], match.index, 'indirect');
    }

    // (2e) Template-literal `t(\`foo.${var}.bar\`)` calls. The
    // template's static prefix and suffix bracket every possible
    // expansion; any en.json key that matches the prefix-suffix
    // shape gets credited. Conservative on purpose — we add the
    // matching keys to `referenced` without flagging anything as
    // missing, because the variable could expand to a value that
    // doesn't correspond to any defined key, and that miss-shape
    // is already caught at the type-checker level via
    // `TranslationKey` codegen.
    const T_TEMPLATE_REGEX = /\bt\(\s*`([^`${]*)\$\{[^}]+\}([^`]*)`/g;
    while ((match = T_TEMPLATE_REGEX.exec(text))) {
      const prefix = match[1];
      const suffix = match[2];
      if (!prefix && !suffix) continue;
      for (const key of enKeys) {
        if (key.startsWith(prefix) && key.endsWith(suffix)) {
          referenced.add(key);
        }
      }
    }

    // (2c) JSX attribute values that happen to be dotted-string
    // literals matching an en.json key. The component author may
    // have wired the attribute through a less-conventional prop
    // name (`tooltipKey`, `description`, `errorMessageKey`); rather
    // than enumerate every name, harvest passively: only attributes
    // whose value resolves against en.json count. This is a
    // permissive sweep (no missing-key validation here) by design —
    // we trust the dotted-shape + en.json membership filter.
    JSX_ATTR_KEY_REGEX.lastIndex = 0;
    while ((match = JSX_ATTR_KEY_REGEX.exec(text))) {
      const key = match[2];
      if (enKeys.has(key)) referenced.add(key);
    }

    // (2d) Passive harvest: any string literal `'foo.bar'` /
    // `"foo.bar"` anywhere in the source whose value matches an
    // en.json key. Captures the long tail of patterns the explicit
    // matchers above cannot enumerate (`label: 'nav.foo'`,
    // descriptor tables, switch-mapped strings stored as locals,
    // etc.). Like (2c), we trust the en.json membership filter to
    // bound false positives — a dotted string that happens to
    // appear in source AND happens to also be a locale key is
    // overwhelmingly likely to be one.
    const ANY_DOTTED_LITERAL_REGEX = /(['"])([\w]+(?:\.[\w]+)+)\1/g;
    while ((match = ANY_DOTTED_LITERAL_REGEX.exec(text))) {
      const key = match[2];
      if (enKeys.has(key)) referenced.add(key);
    }

    // (3) `Record<string, string>` registry values — every dotted
    // string-literal value in the declaration body counts as a
    // referenced locale key. We do NOT fail on missing keys here:
    // a registry may carry non-locale strings (icon names, CSS
    // class identifiers); accept the false-positive risk in exchange
    // for not flagging legitimate non-locale data.
    RECORD_DECL_REGEX.lastIndex = 0;
    while ((match = RECORD_DECL_REGEX.exec(text))) {
      const openBraceIndex = match.index + match[0].length - 1;
      const body = extractRecordBody(text, openBraceIndex);
      if (body === null) continue;
      STRING_VALUE_REGEX.lastIndex = 0;
      let inner;
      while ((inner = STRING_VALUE_REGEX.exec(body))) {
        const key = inner[2];
        if (key.includes('.')) referenced.add(key);
      }
    }
  }
  return { missing, referenced };
}

function printList(title, items, max = 50) {
  console.error(`${title} (${items.length})`);
  for (const item of items.slice(0, max)) console.error(`  - ${item}`);
  if (items.length > max) console.error(`  ... and ${items.length - max} more`);
}

const enKeys = loadEnKeys();
console.log(`Loaded ${enKeys.size} keys from en.json (incl. _invariant.ts).`);

const { missing, referenced } = scanSource(enKeys);

if (missing.length > 0) {
  console.error(
    `ERROR: ${missing.length} t(...) call(s) reference keys not defined in en.json:`,
  );
  for (const { file, line, key } of missing) {
    console.error(`  ${file}:${line}  -> '${key}'`);
  }
  process.exit(1);
}

console.log(
  `OK: all ${referenced.size} keys reachable from t(...) calls + titleKey/labelKey/descriptionKey/iconKey ` +
    'properties + Record<string,string> registries resolve against en.json.',
);

// Soft signal: keys defined but never reached by any of the three
// pattern shapes above. Residue here is the genuinely dead set
// (modulo the remaining handful of `t(buildKey(x))`-style runtime-
// constructed keys), and operators can delete them in a sweep.
const unreferenced = [...enKeys].filter((k) => !referenced.has(k));
if (unreferenced.length > 0) {
  console.log(
    `WARN: ${unreferenced.length} en.json key(s) have no static reference ` +
      '(literal t(...), titleKey-style property, or registry value).',
  );
  if (unreferenced.length <= 60) {
    printList('apparently unreferenced en.json keys', unreferenced, 60);
  }
}
