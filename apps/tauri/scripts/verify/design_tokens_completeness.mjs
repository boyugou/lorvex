#!/usr/bin/env node
/**
 * #3673 — design-tokens completeness gate.
 *
 * Ensures the token families called out as canonical in
 * `docs/design/DESIGN_TOKENS.md` stay aligned with the declarations in
 * `app/src/index.css`. Specifically: every `--token-name:` declaration
 * in the CSS that matches one of the audited family prefixes must
 * appear at least once in the design-tokens markdown catalog.
 *
 * Scope: this gate intentionally does NOT cover the entire CSS
 * surface. The catalog grew alongside the codebase and full coverage
 * is a separate documentation effort (#3673 follow-up). The audited
 * families are the ones whose token names directly drive theme/profile
 * compositions and whose drift would silently break a retune:
 *
 *   - --profile-material-*
 *   - --shell-card-*
 *   - --shell-panel-*
 *   - --structural-panel-*
 *   - --profile-radius-scale, --theme-radius, --theme-radius-sm,
 *     --theme-radius-lg
 *
 * The allowlist below covers tokens that legitimately live in
 * theme/profile blocks but are intentionally undocumented here (e.g.
 * vendor-prefixed Adwaita primitives that only the adwaita theme
 * consumes — they ride the catalog of their owning theme block, not
 * the cross-theme catalog).
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
    console.error(`[design_tokens_completeness] ERROR: missing file ${p}`);
    process.exit(1);
  }
  return fs.readFileSync(p, 'utf8');
}

readOrFail(cssPath);
const cssSource = resolveCssImportGraph(cssPath);
const docsSource = readOrFail(docsPath);

const AUDITED_PREFIXES = [
  '--profile-material-',
  '--shell-card-',
  '--shell-panel-',
  '--structural-panel-',
];
const AUDITED_EXACT = new Set([
  '--profile-radius-scale',
  '--theme-radius',
  '--theme-radius-sm',
  '--theme-radius-lg',
]);

// Allowlist: tokens that match an audited prefix but are intentionally
// out of scope (vendor primitives, profile-internal temporary notes, etc.).
const ALLOWLIST = new Set([
  // none yet — every audited token is documented as of #3673.
]);

const declared = new Set();
for (const match of cssSource.matchAll(/(--[a-zA-Z0-9_-]+)\s*:/g)) {
  const name = match[1];
  if (AUDITED_EXACT.has(name) || AUDITED_PREFIXES.some((p) => name.startsWith(p))) {
    if (!ALLOWLIST.has(name)) declared.add(name);
  }
}

const missing = [];
for (const token of [...declared].sort()) {
  // Match the bare token name anywhere in the catalog (a code-fence
  // mention, a bullet description, a heading id all count as "this
  // token has a documented role").
  if (!docsSource.includes(token)) missing.push(token);
}

if (missing.length > 0) {
  console.error('[design_tokens_completeness] ERROR: tokens declared in app/src/index.css but missing from docs/design/DESIGN_TOKENS.md:');
  for (const token of missing) console.error(`  ${token}`);
  console.error('');
  console.error('Either document the token in the canonical catalog or, if it is genuinely out of scope (vendor-only primitive, etc.), add it to the ALLOWLIST in this script with a comment.');
  process.exit(1);
}

console.log(`[design_tokens_completeness] OK: ${declared.size} audited tokens are all documented in docs/design/DESIGN_TOKENS.md`);
