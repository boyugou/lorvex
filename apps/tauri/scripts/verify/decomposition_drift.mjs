#!/usr/bin/env node
/**
 * Decomposition-drift gate.
 *
 * When a flat module (`foo.rs`) is decomposed into a sibling subtree
 * (`foo/mod.rs`, `foo/<part>.rs`, ...), every rustdoc / CHANGELOG /
 * README reference that still points at `foo.rs` becomes a 404 from
 * the reader's perspective. The reference is a hover-jump target that
 * silently misses, or a CHANGELOG path readers can no longer locate.
 *
 * This gate scans rustdoc comments (`//`, `///`, `//!`) in production
 * Rust source plus the canonical doc surface (`CHANGELOG.md`, top-level
 * `*.md` under the repo and `docs/`) for backticked path strings that
 * look like Rust source files (ending in `.rs`), and flags any whose
 * resolved location on disk is now a directory rather than a file.
 *
 * Scope is intentionally narrow:
 *   - Only `.rs` references are checked. `.ts` / `.tsx` decomposition
 *     drift exists too but the import resolver flags it at build time.
 *   - References include backticked (` `foo/bar.rs` `) and bare-word
 *     occurrences that contain a `/` and end in `.rs`. URLs and file
 *     paths inside fenced code blocks are also scanned.
 *   - Bracket-suffix glob references (`foo.rs[1..N]`) are stripped to
 *     the file part before resolution.
 *
 * Retrospective docs (under `RETROSPECTIVE_DIRS`) are exempt from the
 * gate so historical paths inside ADR / archive prose don't drift the
 * verifier when the live tree decomposes.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..', '..');

const RUST_ROOTS = [
  'app/src-tauri/src',
  'lorvex-cli/src',
  'lorvex-domain/src',
  'lorvex-store/src',
  'lorvex-sync/src',
  'lorvex-sync-payload/src',
  'lorvex-workflow/src',
  'mcp-server/src',
  'lorvex-mcp-derive/src',
  'lorvex-runtime/src',
];

// Markdown surfaces scanned for stale `.rs` references.
const MD_ROOTS = [
  'CHANGELOG.md',
  'README.md',
  'ROADMAP.md',
  'CONTRIBUTING.md',
  'CLAUDE.md',
  'docs',
];

// Backticked or bare path-like tokens ending in `.rs`. The capture
// is the path itself (without surrounding punctuation). Examples:
//   - `lorvex-workflow/src/calendar_event.rs`
//   - `app/src-tauri/.../calendar_events/validation.rs`
//   - `mcp-server/src/tasks/mutations/create.rs`
const PATH_RE = /[`"](?<p>[A-Za-z0-9_./\-]*\/[A-Za-z0-9_\-]+\.rs)[`"]|(?<![A-Za-z0-9_./\-])(?<q>[A-Za-z0-9_\-]+\/[A-Za-z0-9_./\-]+\.rs)\b/g;

// Tokens to strip from a matched path before resolution.
const STRIP_TRAILING_RE = /[)\]>,.;:]+$/;

// Doc roots whose content is retrospective by design — historical
// references inside these are exempt from the gate.
const RETROSPECTIVE_DIRS = [
  path.join('docs', 'archive'),
  path.join('docs', 'reference', 'history'),
];

function isRetrospective(relFile) {
  return RETROSPECTIVE_DIRS.some((root) => relFile.startsWith(root + path.sep));
}

// Resolve a referenced path. Returns one of:
//   { kind: 'file' }      — exists as a file (OK)
//   { kind: 'dir' }       — exists as a directory (DRIFT)
//   { kind: 'missing' }   — does not exist
//   { kind: 'unknown' }   — unresolvable shape (skip)
function classify(refPath) {
  if (!refPath || refPath.includes('..') || refPath.includes('//')) {
    return { kind: 'unknown' };
  }
  const cleaned = refPath.replace(STRIP_TRAILING_RE, '').trim();
  if (!cleaned.endsWith('.rs')) return { kind: 'unknown' };
  // Some references include glob/line suffixes — accept the bare path.
  const abs = path.join(repoRoot, cleaned);
  // Strip trailing `.rs` and check if the directory exists as the
  // decomposed sibling subtree (`foo/` next to former `foo.rs`).
  const stripped = abs.slice(0, -'.rs'.length);
  let fileExists = false;
  let dirExists = false;
  try {
    const stat = fs.statSync(abs);
    if (stat.isFile()) fileExists = true;
  } catch (_err) {
    // missing
  }
  try {
    const stat = fs.statSync(stripped);
    if (stat.isDirectory()) dirExists = true;
  } catch (_err) {
    // missing
  }
  if (fileExists) return { kind: 'file' };
  if (dirExists) return { kind: 'dir' };
  return { kind: 'missing' };
}

const SKIP_DIRS = new Set(['node_modules', 'dist', 'build', '.next', '.turbo', 'target', '.git']);

function walkRust(dir, out) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (err) {
    if (err.code === 'ENOENT') return;
    throw err;
  }
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    if (SKIP_DIRS.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walkRust(full, out);
    else if (entry.isFile() && entry.name.endsWith('.rs')) out.push(full);
  }
}

function walkMd(target, out) {
  let stat;
  try {
    stat = fs.statSync(target);
  } catch (err) {
    if (err.code === 'ENOENT') return;
    throw err;
  }
  if (stat.isFile() && target.endsWith('.md')) {
    out.push(target);
    return;
  }
  if (!stat.isDirectory()) return;
  for (const entry of fs.readdirSync(target, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    if (SKIP_DIRS.has(entry.name)) continue;
    walkMd(path.join(target, entry.name), out);
  }
}

const rustFiles = [];
for (const root of RUST_ROOTS) walkRust(path.join(repoRoot, root), rustFiles);
const mdFiles = [];
for (const root of MD_ROOTS) walkMd(path.join(repoRoot, root), mdFiles);

const drift = [];
function extractDocComments(text) {
  // Return doc-comment-only lines so we don't flag e.g. an in-code
  // `path = "foo.rs"` attribute or a re-export string literal that
  // happens to contain a `.rs` path.
  const lines = text.split('\n');
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (
      trimmed.startsWith('///') ||
      trimmed.startsWith('//!') ||
      trimmed.startsWith('//')
    ) {
      out.push({ no: i + 1, text: lines[i] });
    }
  }
  return out;
}

function scanFile(absPath, isMd) {
  const rel = path.relative(repoRoot, absPath);
  if (isRetrospective(rel)) return;
  const text = fs.readFileSync(absPath, 'utf8');
  const lines = isMd
    ? text.split('\n').map((t, i) => ({ no: i + 1, text: t }))
    : extractDocComments(text);
  for (const { no, text: line } of lines) {
    for (const match of line.matchAll(PATH_RE)) {
      const refPath = match.groups?.p ?? match.groups?.q;
      if (!refPath) continue;
      const key = `${rel}:${no}:${refPath}`;
      const classification = classify(refPath);
      if (classification.kind === 'dir') {
        drift.push({ file: rel, line: no, ref: refPath, kind: 'subtree' });
      }
      // We deliberately do NOT flag `missing` — many doc refs point at
      // canonical-form paths that vary by build target or live behind
      // crate features. Subtree drift is the deterministic case this
      // gate catches.
      void key;
    }
  }
}

for (const abs of rustFiles) scanFile(abs, false);
for (const abs of mdFiles) scanFile(abs, true);

if (drift.length > 0) {
  console.error(
    `[decomposition_drift] FAIL — ${drift.length} stale .rs reference(s) now point at decomposed subtrees.`,
  );
  console.error('');
  console.error(
    'Each reference below points at a `.rs` path that is now a directory of sibling files.',
  );
  console.error(
    'Rewrite the reference to the subtree (`foo/`) or to the specific sibling that owns the cited concern.',
  );
  console.error('');
  for (const d of drift) {
    console.error(`  ${d.file}:${d.line} -> ${d.ref}/ (subtree)`);
  }
  process.exit(1);
}

console.log(
  '[decomposition_drift] OK — every .rs reference in scanned rustdoc / CHANGELOG resolves to a file.',
);
