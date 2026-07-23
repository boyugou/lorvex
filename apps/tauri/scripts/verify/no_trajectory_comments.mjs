#!/usr/bin/env node
/**
 * Trajectory-comment gate.
 *
 * Code comments and docstrings are reference material for someone
 * reading current code today. Two reader-hostile forms keep leaking
 * back in and this gate rejects them:
 *
 *   1. `#NNNN` PR-number anchors — short polish-style cross-references
 *      like `// #4419 — j/k roving focus across the day panel` or
 *      `// R2 polish (#4386): tag the just-moved card`. The PR has
 *      long since merged; the anchor adds no contract a reader
 *      hovering the line can act on.
 *
 *   2. Trajectory narratives — `previously / used to / formerly /
 *      originally` framings that describe the development path
 *      instead of the current state ("Pre-fix the toggle ..." or
 *      "this previously open-coded the literal").
 *
 * Both belong in PR descriptions, commit messages, or dedicated
 * retrospective docs (CHANGELOG, ADRs) — never in the docstring a
 * reader lands on via hover-jump.
 *
 * Scope is rule-specific:
 *
 *   - Trajectory narratives are gated across every production source
 *     root — TS/TSX under `app/src` plus every workspace Rust crate
 *     (`app/src-tauri/src`, `lorvex-cli/src`, `lorvex-domain/src`,
 *     `lorvex-store/src`, `lorvex-sync/src`, `lorvex-sync-payload/src`,
 *     `lorvex-workflow/src`, `mcp-server/src`).
 *   - `#NNNN` PR-number anchors are gated only on `app/src` and
 *     `lorvex-workflow/src`. The wider Rust tree carries a large body
 *     of legitimate issue cross-references that the project keeps as
 *     reference material; the trajectory-narrative rule is the one
 *     that needs system-wide coverage.
 *
 * Test files (matching *test*, paths under tests/, and test_support*)
 * are exempt under both rules — test docstrings legitimately cite the
 * issue a regression test was written against.
 *
 * Exempt API contracts: Win32/EventKit/CoreGraphics docstrings that
 * say "previously-selected GDI bitmap" are load-bearing OS-API
 * vocabulary, not trajectory narrative. These are not currently
 * present in the gated scope; if they appear, extend the
 * `LOAD_BEARING_API_LINES` allowlist below.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..', '..');

const RUST_EXT = new Set(['.rs']);

// Two-tier scope. The trajectory-narrative rule applies to every
// production source root (TS/TSX under `app/src` plus every workspace
// Rust crate). The `#NNNN` PR-anchor rule is gated to the two roots
// that have been swept clean of those anchors and must stay clean —
// the wider Rust tree still carries a large body of legitimate issue
// cross-references that aren't part of this verifier's mandate.
const TRAJECTORY_ROOTS = [
  { root: path.join(repoRoot, 'app', 'src'), extensions: new Set(['.ts', '.tsx']) },
  { root: path.join(repoRoot, 'app', 'src-tauri', 'src'), extensions: RUST_EXT },
  { root: path.join(repoRoot, 'lorvex-cli', 'src'), extensions: RUST_EXT },
  { root: path.join(repoRoot, 'lorvex-domain', 'src'), extensions: RUST_EXT },
  { root: path.join(repoRoot, 'lorvex-store', 'src'), extensions: RUST_EXT },
  { root: path.join(repoRoot, 'lorvex-sync', 'src'), extensions: RUST_EXT },
  { root: path.join(repoRoot, 'lorvex-sync-payload', 'src'), extensions: RUST_EXT },
  { root: path.join(repoRoot, 'lorvex-workflow', 'src'), extensions: RUST_EXT },
  { root: path.join(repoRoot, 'mcp-server', 'src'), extensions: RUST_EXT },
];
const PR_ANCHOR_ROOTS = [
  { root: path.join(repoRoot, 'app', 'src'), extensions: new Set(['.ts', '.tsx']) },
  { root: path.join(repoRoot, 'lorvex-workflow', 'src'), extensions: RUST_EXT },
];

const SKIP_DIRS = new Set(['node_modules', 'dist', 'build', '.next', '.turbo', 'target']);

// Files exempt from the gate: tests and test-support fixtures.
function isTestPath(rel) {
  if (rel.includes('/tests/')) return true;
  const base = path.basename(rel);
  if (base.includes('.test.')) return true;
  if (base.includes('.spec.')) return true;
  if (base.startsWith('test_support')) return true;
  // Idiomatic Rust child-tests modules — `tests.rs` next to its
  // sibling production module — legitimately cite the regression
  // shape a test exists to pin.
  if (base === 'tests.rs') return true;
  return false;
}

// Load-bearing OS-API references where "previously-selected" / etc.
// is OS-vendor vocabulary rather than trajectory narrative.
// Format: `${relPath}:${lineNo}`. Empty by design — add entries with
// a one-line justification if a genuine Win32/EventKit/CoreGraphics
// API contract requires this vocabulary.
const LOAD_BEARING_API_LINES = new Set([]);

// Pattern 1: `#NNNN` anchor inside a line comment, doc comment, or
// block-comment continuation. Captures both `//` and `///` JS/Rust
// line comments, `//!` Rust module-doc comments, and ` * ` block
// continuations.
const PR_NUMBER_RE = /(?:\/\/\/?!?|\s\*|\/\*\*?|^\s*\*).*#\d{3,5}\b/;

// Pattern 2: trajectory narratives. Word-boundary match on a family of
// development-history triggers (`previously`, `formerly`, `originally`,
// `historically`, `used to`, `prior to <code-noun>`, `before this <code-noun>`,
// `the old <code-noun>`, `legacy <shape-word>`, `pre-fix`, `pre-#NNNN`).
//
// Hyphenated participial forms like `previously-archived task` describe a
// current-state entity ("a task that was archived") rather than a
// development trajectory, so the regex requires a whitespace boundary
// after a bare `previously / formerly / originally` trigger. Similarly
// `historically-seen` describes a current-state runtime shape and is
// excluded; the standalone adverb `historically` is the narrative form.
//
// `prior to`, `before this`, and `the old` all have legitimate runtime
// readings ("the old value the row carried before this UPDATE ran",
// "the OLD timezone the user just left"). They are narrative only when
// they qualify a code-shape noun (`prior to this newtype`, `before this
// module landed`, `the old struct shape`). The CODE_SHAPE_NOUN whitelist
// below captures the discriminator.
//
// `legacy` is only narrative when it qualifies a shape/contract noun
// — bare `legacy <noun>` constructions like "legacy field" are
// already-shipped narrative framing. The whitelist of qualifying
// shape-words below catches the actual leak patterns; standalone
// `legacy` as part of a domain term (e.g. file paths) is left alone.
const LEGACY_SHAPE_WORDS =
  'shape|behavior|behaviour|path|contract|approach|struct|five-key|column[- ]split|two-?(?:column|field)';
// Code-shape nouns that turn `prior to ...`, `before this ...`, `the old ...`
// from runtime-state language into development-trajectory framing. The
// list is deliberately narrow — runtime "before this UPDATE" or "the old
// timezone value" must keep reading as runtime semantics.
// Code-shape nouns chosen to discriminate trajectory framing from
// runtime semantics. Avoid runtime-overloaded terms (`update`, `column`,
// `field`, `value`, `version`, `row`) — those legitimately appear in
// runtime ordering language ("before this update runs", "the old value
// the row carried").
const CODE_SHAPE_NOUNS =
  '(?:fix|module|view|patch|enum|newtype|hoist|helper|classifier|banner|typed|tree|files?|struct|shape|class|trait|name|migration|crate|layer|wrapper|design|sweep|sweeper|behavi(?:or|our)|approach|contract|signature|caller\\s+contract|interface|registry|inline|hand-rolled|monolith|flat\\s+tree|sub-?tree|directory|dir|impl|implementation|gate|guard|stamp|envelope|protocol|verifier|builder|orchestrator|finalizer|hooks?|reducer)\\b';
const NARRATIVE_RE = new RegExp(
  '(?:\\/\\/\\/?!?|\\s\\*|\\/\\*\\*?|^\\s*\\*).*(?:' +
    '\\b(?:previously|formerly|originally)\\s' +
    '|\\bused\\s+to\\b' +
    '|\\bpre-fix\\b' +
    '|\\bpre-#\\d+\\b' +
    '|\\bhistorically\\b' +
    '|\\bprior\\s+to\\s+(?:this\\s+|the\\s+|a\\s+)?' + CODE_SHAPE_NOUNS +
    '|\\bbefore\\s+this\\s+' + CODE_SHAPE_NOUNS +
    '|\\bthe\\s+old\\s+(?:flat\\s+)?' + CODE_SHAPE_NOUNS +
    '|\\blegacy\\s+(?:' + LEGACY_SHAPE_WORDS + ')\\b' +
    ')',
  'i',
);
const LEGACY_SHAPE_RE = new RegExp(
  '\\blegacy\\s+(?:' + LEGACY_SHAPE_WORDS + ')\\b',
  'i',
);
const HISTORICALLY_ADVERB_RE = /\bhistorically\b(?!-)/i;
const HISTORICALLY_PARTICIPLE_RE = /\bhistorically-/i;
const PRIOR_TO_NARRATIVE_RE = new RegExp(
  '\\bprior\\s+to\\s+(?:this\\s+|the\\s+|a\\s+)?' + CODE_SHAPE_NOUNS,
  'i',
);
const BEFORE_THIS_NARRATIVE_RE = new RegExp(
  '\\bbefore\\s+this\\s+' + CODE_SHAPE_NOUNS,
  'i',
);
const THE_OLD_NARRATIVE_RE = new RegExp(
  '\\bthe\\s+old\\s+(?:flat\\s+)?' + CODE_SHAPE_NOUNS,
  'i',
);

// "used to" functional false positives — e.g. "is used to dedupe",
// "are used to compute". These describe what something is for, not a
// historical narrative. Exclude when "used to" is preceded by a
// passive copula.
const FUNCTIONAL_USED_TO_RE = /\b(is|are|was|were|be|been|being)\s+used\s+to\b/i;

function lineIsNarrative(line) {
  if (!NARRATIVE_RE.test(line)) return false;
  // `previously / formerly / originally` followed by whitespace are
  // always narrative. Hyphenated forms (`previously-archived`) are
  // participial adjectives describing a current-state entity and were
  // already excluded by NARRATIVE_RE.
  if (/\b(?:previously|formerly|originally)\s/i.test(line)) return true;
  // `pre-fix` / `prefix` (only when used as a phase marker — the noun
  // "prefix" itself is allowed) and `pre-#NNNN` PR anchors are always
  // narrative trajectory framings ("Pre-fix the toggle accepted X").
  // The "prefix" word as in "string prefix" / "BYDAY prefix" is a
  // common false positive — exclude it.
  if (/\bpre-#\d+\b/i.test(line)) return true;
  if (/\bpre-fix\b/i.test(line)) return true;
  // `historically` as a standalone adverb is narrative; the hyphenated
  // `historically-seen` form is a participial adjective describing a
  // current-state runtime shape.
  if (HISTORICALLY_ADVERB_RE.test(line) && !HISTORICALLY_PARTICIPLE_RE.test(line)) {
    return true;
  }
  // `prior to / before this / the old` are narrative only when followed
  // by a code-shape noun. Runtime readings ("the old value the row
  // carried before this UPDATE ran") stay allowed.
  if (PRIOR_TO_NARRATIVE_RE.test(line)) return true;
  if (BEFORE_THIS_NARRATIVE_RE.test(line)) return true;
  if (THE_OLD_NARRATIVE_RE.test(line)) return true;
  if (LEGACY_SHAPE_RE.test(line)) return true;
  // Lone "used to" — verify it is not the functional "is used to"
  // shape.
  if (/\bused\s+to\b/i.test(line)) {
    return !FUNCTIONAL_USED_TO_RE.test(line);
  }
  return false;
}

const violations = [];
const seenViolations = new Map();
function record(key, rule) {
  let s = seenViolations.get(key);
  if (!s) {
    s = new Set();
    seenViolations.set(key, s);
  }
  s.add(rule);
}

function walk(dir, extensions, checks) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (error) {
    if (error.code === 'ENOENT') return;
    throw error;
  }
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    if (SKIP_DIRS.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, extensions, checks);
      continue;
    }
    if (!entry.isFile()) continue;
    if (!extensions.has(path.extname(entry.name))) continue;
    const rel = path.relative(repoRoot, full);
    if (isTestPath(rel)) continue;
    const text = fs.readFileSync(full, 'utf8');
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const lineNo = i + 1;
      const line = lines[i];
      const exemptKey = `${rel}:${lineNo}`;
      if (LOAD_BEARING_API_LINES.has(exemptKey)) continue;
      const seen = seenViolations.get(exemptKey);
      if (checks.prAnchor && PR_NUMBER_RE.test(line) && !(seen && seen.has('pr_number_anchor'))) {
        violations.push({ rule: 'pr_number_anchor', file: rel, line: lineNo, text: line.trim() });
        record(exemptKey, 'pr_number_anchor');
      }
      if (checks.trajectory && lineIsNarrative(line) && !(seen && seen.has('trajectory_narrative'))) {
        violations.push({ rule: 'trajectory_narrative', file: rel, line: lineNo, text: line.trim() });
        record(exemptKey, 'trajectory_narrative');
      }
    }
  }
}

for (const { root, extensions } of TRAJECTORY_ROOTS) {
  walk(root, extensions, { trajectory: true, prAnchor: false });
}
for (const { root, extensions } of PR_ANCHOR_ROOTS) {
  walk(root, extensions, { trajectory: false, prAnchor: true });
}

if (violations.length > 0) {
  console.error(
    `[no_trajectory_comments] FAIL — ${violations.length} trajectory comment(s) in production source.`,
  );
  console.error('');
  console.error(
    'Forbidden forms (scope is rule-specific — see file header):',
  );
  console.error(
    '  - `#NNNN` PR-number anchors (e.g. `// #4397 — Left-rail accent`) — gated on app/src + lorvex-workflow/src.',
  );
  console.error(
    '  - Trajectory narratives (previously / used to / formerly / originally) — gated on every production root.',
  );
  console.error(
    'Rewrite in current-state form — describe what the code does today, not how it got there.',
  );
  console.error('');
  for (const v of violations) {
    console.error(`  ${v.file}:${v.line} [${v.rule}] ${v.text}`);
  }
  process.exit(1);
}

console.log(
  '[no_trajectory_comments] OK — no #NNNN anchors or trajectory narratives in gated source.',
);
