#!/usr/bin/env node
/**
 * Audit #3052-H1: cross-manifest dependency-major alignment.
 *
 * Lorvex carries two independent Cargo workspaces:
 *
 *   • Root `Cargo.toml` (`[workspace.dependencies]`) — declares the
 *     canonical version range used by every member crate that opts in
 *     via `<dep> = { workspace = true }`.
 *
 *   • `app/src-tauri/Cargo.toml` — a standalone workspace that cannot
 *     inherit `[workspace.dependencies]`. It re-declares its own deps,
 *     and historically each one was hand-maintained. A loose-pin in the
 *     root (`chrono = "0.4"`) would silently drift from the Tauri side
 *     because nothing checked the two manifests against one another.
 *
 * This verifier walks every dependency declared in the root workspace's
 * `[workspace.dependencies]` table that is also declared in
 * `app/src-tauri/Cargo.toml`, parses each version requirement (skipping
 * exact-pinned `=x.y.z` entries — those are Tauri-family critical-path
 * crates governed by the #2299 / #2931-M1 exact-pin policy) and asserts
 * that the major (and major.minor for `0.x` semver) match. A mismatch
 * means the desktop app and the headless workspace would resolve
 * different versions of the same crate, which Cargo.lock unification
 * cannot easily fix.
 *
 * The verifier is intentionally minimum-viable: it does not parse the
 * full TOML grammar; it walks `[workspace.dependencies]` and the top-
 * level `[dependencies]` block of `app/src-tauri/Cargo.toml` line-by-
 * line. Both blocks are flat key/value tables in this repo today, and
 * any future structure change that breaks this parser is exactly the
 * kind of drift the verifier should flag.
 *
 * CLI:
 *   node scripts/verify/cargo_deps_aligned.mjs           → exit 0 clean
 *   node scripts/verify/cargo_deps_aligned.mjs --check   → alias
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');

const ROOT_MANIFEST = path.join(REPO_ROOT, 'Cargo.toml');
const APP_MANIFEST = path.join(REPO_ROOT, 'app', 'src-tauri', 'Cargo.toml');

/**
 * Extract the body of a top-level TOML table. Returns the lines between
 * the table header `[name]` and the next top-level `[...]` header.
 *
 * Limitation: cannot handle nested array-of-tables (`[[name]]`) or
 * sub-tables (`[name.sub]`); none of the manifests we read use those.
 */
function extractTableBody(toml, header) {
  const lines = toml.split(/\r?\n/);
  let inTable = false;
  const out = [];
  const headerRe = new RegExp(`^\\s*\\[${header.replace(/\./g, '\\.')}\\]\\s*$`);
  const otherHeaderRe = /^\s*\[[^\]]+\]\s*$/;
  for (const line of lines) {
    if (!inTable) {
      if (headerRe.test(line)) inTable = true;
      continue;
    }
    if (otherHeaderRe.test(line)) break;
    out.push(line);
  }
  return out.join('\n');
}

/**
 * Parse a single `<key> = <value>` declaration into `{ name, version }`.
 * Returns `null` if the declaration is a comment, empty, or the version
 * cannot be extracted (e.g. workspace-path deps, `workspace = true`).
 *
 * Supported value shapes:
 *   foo = "1.2"
 *   foo = "=1.2.3"
 *   foo = { version = "1.2", features = [...] }
 *   foo = { path = "../foo" }                              (skipped)
 *   foo = { workspace = true }                              (skipped)
 */
function parseDepLine(line) {
  const stripped = line.replace(/#.*$/, '').trim();
  if (!stripped) return null;
  const m = stripped.match(/^([A-Za-z0-9_-]+)\s*=\s*(.+?)\s*$/);
  if (!m) return null;
  const name = m[1];
  const value = m[2];
  // Bare-string version: `foo = "1.2"`
  const bare = value.match(/^"([^"]+)"$/);
  if (bare) return { name, version: bare[1] };
  // Inline-table form: extract `version = "..."`. Skip workspace/path.
  if (value.startsWith('{')) {
    if (/\bworkspace\s*=\s*true\b/.test(value)) return null;
    if (/\bpath\s*=\s*"/.test(value) && !/\bversion\s*=\s*"/.test(value)) return null;
    const v = value.match(/\bversion\s*=\s*"([^"]+)"/);
    if (v) return { name, version: v[1] };
    return null;
  }
  return null;
}

function parseTable(body) {
  const out = new Map();
  // Naive multi-line inline-table join: a line that opens `{` and does
  // not close it is concatenated with the following lines until the
  // matching `}`. None of the manifests we read use that pattern today,
  // but the join keeps the parser robust if one is added later.
  let buf = '';
  let depth = 0;
  for (const raw of body.split(/\r?\n/)) {
    const line = raw;
    const stripped = line.replace(/#.*$/, '');
    for (const c of stripped) {
      if (c === '{') depth++;
      else if (c === '}') depth--;
    }
    buf = buf ? buf + ' ' + line.trim() : line;
    if (depth <= 0) {
      const parsed = parseDepLine(buf);
      if (parsed) out.set(parsed.name, parsed.version);
      buf = '';
      depth = 0;
    }
  }
  return out;
}

/**
 * Normalize a Cargo version requirement to a comparable major skeleton.
 *
 * Cargo's default caret semantics treat `1`, `1.2`, `1.2.3` as compatible
 * with the same major (1.x.x). For `0.x` releases the minor acts as the
 * major (`0.4` and `0.4.7` are compatible; `0.4` and `0.5` are not).
 *
 * Returns the canonical skeleton string, e.g.:
 *   "1"      → "1"
 *   "1.2.3"  → "1"
 *   "0.4"    → "0.4"
 *   "0.4.7"  → "0.4"
 *
 * Returns `null` for exact pins (`=1.2.3`) — alignment is not asserted
 * because exact pins are governed by a separate policy (#2299, #2931-M1)
 * and intentionally diverge between manifests when only one side is on
 * the supply-chain critical path.
 */
function majorSkeleton(req) {
  if (req.startsWith('=')) return null;
  const parts = req.split('.');
  if (parts[0] === '0') {
    if (parts.length < 2) return null;
    return `0.${parts[1]}`;
  }
  return parts[0];
}

function main() {
  const rootToml = fs.readFileSync(ROOT_MANIFEST, 'utf8');
  const appToml = fs.readFileSync(APP_MANIFEST, 'utf8');

  const rootDeps = parseTable(extractTableBody(rootToml, 'workspace.dependencies'));
  const appDeps = parseTable(extractTableBody(appToml, 'dependencies'));

  const errors = [];
  const checked = [];

  for (const [name, rootReq] of rootDeps) {
    if (!appDeps.has(name)) continue;
    const appReq = appDeps.get(name);
    const rootSkel = majorSkeleton(rootReq);
    const appSkel = majorSkeleton(appReq);
    // Either side exact-pinned → out of scope for this verifier.
    if (rootSkel === null || appSkel === null) continue;
    if (rootSkel !== appSkel) {
      errors.push(
        `dependency \`${name}\`: root workspace pins \`${rootReq}\` (major ${rootSkel}), ` +
          `but app/src-tauri pins \`${appReq}\` (major ${appSkel}).`,
      );
    } else {
      checked.push(`${name}: root=${rootReq} app=${appReq} (major ${rootSkel})`);
    }
  }

  if (errors.length > 0) {
    console.error('cargo_deps_aligned: cross-manifest version drift detected:\n');
    for (const e of errors) console.error('  ✗ ' + e);
    console.error(
      '\nFix: align the major (and minor for 0.x) of each listed crate ' +
        'in `Cargo.toml` and `app/src-tauri/Cargo.toml`, or escalate one ' +
        'side to an exact pin (`=x.y.z`) so the verifier intentionally ' +
        'skips it.',
    );
    process.exit(1);
  }

  console.log(`cargo_deps_aligned: ok — checked ${checked.length} shared dependency declaration(s).`);
  for (const c of checked) console.log('  ✓ ' + c);
}

main();
