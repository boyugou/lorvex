#!/usr/bin/env node
/**
 * #4435 — utility-completeness gate.
 *
 * Every `@utility <name>` block declared anywhere in
 * `app/src/index.css` (and the files it `@import`s) must appear at
 * least once as a bare token in `docs/design/DESIGN_TOKENS.md`. The
 * catalog is the canonical contract for what each utility means and
 * when to reach for it; an undocumented utility drifts on the next
 * retune (the call site is the only place that knows the recipe).
 *
 * Pair gate to `verify:design-tokens-completeness` which enforces the
 * same rule for the audited `--token` families.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { resolveCssImportGraph } from '../lib/css_graph.mjs';

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');
const cssPath = path.join(repoRoot, 'app/src/index.css');
const docsPath = path.join(repoRoot, 'docs/design/DESIGN_TOKENS.md');

function readOrFail(p) {
  if (!fs.existsSync(p)) {
    console.error(`[utility_completeness] ERROR: missing file ${p}`);
    process.exit(1);
  }
  return fs.readFileSync(p, 'utf8');
}

readOrFail(cssPath);
const cssSource = resolveCssImportGraph(cssPath);
const docsSource = readOrFail(docsPath);

// Allowlist: utilities that are intentionally undocumented in the
// canonical catalog (e.g. dynamically generated families documented
// in prose alongside their token family). Add with a comment naming
// the family / rationale.
const ALLOWLIST = new Set([
  // none yet.
]);

const declared = new Set();
for (const match of cssSource.matchAll(/^\s*@utility\s+([a-zA-Z0-9_-]+)/gm)) {
  const name = match[1];
  if (!ALLOWLIST.has(name)) declared.add(name);
}

// The catalog documents tone-keyed utility families with brace
// expansion — e.g. `chip-{success,warning,danger}-interactive`
// stands in for the three real `@utility` declarations. Expand each
// such pattern in the docs source so the membership check sees the
// concrete names. Plain `${name}` mentions without braces still
// match directly via `docsSource.includes(name)`.
const documented = new Set();
for (const match of docsSource.matchAll(/([a-zA-Z0-9_-]*\{([a-zA-Z0-9_,\s-]+)\}[a-zA-Z0-9_-]*)/g)) {
  const pattern = match[1];
  const opts = match[2].split(',').map((s) => s.trim()).filter(Boolean);
  for (const opt of opts) {
    documented.add(pattern.replace(/\{[^}]+\}/, opt));
  }
}

const missing = [];
for (const name of [...declared].sort()) {
  // Direct mention (code-fence, bullet, heading id) OR a brace-
  // expansion family in the catalog all count as documented.
  if (docsSource.includes(name)) continue;
  if (documented.has(name)) continue;
  missing.push(name);
}

if (missing.length > 0) {
  console.error('[utility_completeness] ERROR: @utility blocks declared in CSS but missing from docs/design/DESIGN_TOKENS.md:');
  for (const name of missing) console.error(`  ${name}`);
  console.error('');
  console.error('Add a catalog entry under "Composed @utility blocks" (or the relevant section) describing name, role, when to use, when not — or, if the utility is genuinely out of scope (dynamically generated family documented in prose), add it to the ALLOWLIST in this script with a comment.');
  process.exit(1);
}

console.log(`[utility_completeness] OK: ${declared.size} @utility blocks are all documented in docs/design/DESIGN_TOKENS.md`);
