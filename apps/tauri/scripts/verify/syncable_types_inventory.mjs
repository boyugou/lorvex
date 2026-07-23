#!/usr/bin/env node
/**
 * Audit #2984-DC-H8: enforce that the canonical syncable-types inventory
 * in `lorvex-domain/src/naming/entity/topology.rs` (`ALL_SYNCABLE_TYPES`)
 * is the single source of truth.
 *
 * Three checks:
 *
 *   1. Parse `ALL_SYNCABLE_TYPES` from `naming/entity/topology.rs`. Resolve
 *      every `ENTITY_*` / `EDGE_*` constant inside the slice to its
 *      underlying string literal (defined in `naming/entity/constants.rs`
 *      and `naming/edge.rs` respectively). The slice is
 *      flat — no programmatic concatenation — so a regex-driven parser
 *      is intentional and stable.
 *
 *   2. For every consumer file that the audit listed as a hot spot, scan
 *      for an inline string-literal SUBSET LIST of the syncable types —
 *      specifically a Rust array/slice/vec literal containing two or
 *      more entity-type string literals (e.g. `&["task", "list",
 *      "habit"]`). That is the failure mode the audit observed: a
 *      hand-maintained parallel list silently drifting from
 *      `ALL_SYNCABLE_TYPES`. Single-literal occurrences (table-name
 *      maps, individual unit-test fixtures) are fine — those are not
 *      parallel inventories. Comments are stripped before scanning.
 *
 * Wire into the `verify:repo-governance` chain via package.json.
 *
 * CLI:
 *   node scripts/verify/syncable_types_inventory.mjs            → exit 0 clean
 *   node scripts/verify/syncable_types_inventory.mjs --check    → alias
 */
import fs from 'node:fs';
import path from 'node:path';

import { resolveRepoRootFromMeta, runVerifierCli } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:syncable-types]';
const REPO_ROOT = resolveRepoRootFromMeta(import.meta.url);

// `naming/entity/` was split into per-concern siblings in #3066: the
// `ENTITY_*` string constants live in `constants.rs` and the
// `ALL_SYNCABLE_TYPES` slice + `TOPOLOGICAL_ENTITY_ORDER` live in
// `topology.rs`. The verifier reads both to reconstitute the inventory
// exactly as the old monolithic `mod.rs` exposed it.
const ENTITY_CONSTANTS_REL = 'lorvex-domain/src/naming/entity/constants.rs';
const ENTITY_TOPOLOGY_REL = 'lorvex-domain/src/naming/entity/topology.rs';
const EDGE_NAMING_REL = 'lorvex-domain/src/naming/edge.rs';

// Each entry is either a file (`.rs`) or a directory module. For directories
// the verifier walks every production `.rs` file recursively, excluding test
// fixtures (anything under a `tests/` segment, `*tests.rs`, or `test_support`).
// `outbox_enqueue` was originally a single 1.5k-line file; the directory form
// (`outbox_enqueue/{mod.rs, child_tombstones.rs, snapshot.rs, …}`) preserves
// the same dispatch surface area split across topical files. Scanning the
// directory keeps the inventory-drift gate honest after that refactor.
// The CLI calendar write surface now lives in the command/effects tree plus
// the dispatch bridge. Keep these entries on the production modules that own
// calendar behavior so inline syncable-type subset lists cannot reappear there.
const CONSUMER_RELS = [
  'mcp-server/src/runtime/change_tracking',
  'lorvex-sync/src/outbox_enqueue',
  'lorvex-sync/src/apply/dispatch',
  'lorvex-cli/src/commands/query/calendar.rs',
  'lorvex-cli/src/commands/mutate/calendar',
  'lorvex-cli/src/dispatch/calendar.rs',
];

function readRel(rel) {
  const abs = path.join(REPO_ROOT, rel);
  if (!fs.existsSync(abs)) {
    throw new Error(`${SCRIPT_TAG} missing required file: ${rel}`);
  }
  return fs.readFileSync(abs, 'utf8');
}

/**
 * Skip test fixture files when walking a directory consumer — those
 * legitimately enumerate every entity type for parametric coverage and would
 * otherwise trip the parallel-inventory detector.
 */
function isTestRustFile(rel) {
  return (
    rel.includes('/tests/')
    || rel.includes('/test_support/')
    || /\btests\.rs$/.test(rel)
    || /\btest_support\.rs$/.test(rel)
  );
}

/**
 * Read a consumer either as a single file or as every production `.rs` in a
 * directory module. Returns one source string ready for the inline-leak
 * scanner; line numbers in offender reports correspond to the concatenated
 * stream when the input is a directory, with a comment header per file so the
 * offender's source is still recoverable.
 */
function readConsumerSource(rel) {
  const abs = path.join(REPO_ROOT, rel);
  if (!fs.existsSync(abs)) {
    throw new Error(`${SCRIPT_TAG} missing required file: ${rel}`);
  }
  const stat = fs.statSync(abs);
  if (stat.isFile()) {
    return [{ rel, source: fs.readFileSync(abs, 'utf8') }];
  }
  if (!stat.isDirectory()) {
    throw new Error(`${SCRIPT_TAG} unsupported consumer entry (not file or directory): ${rel}`);
  }
  const files = [];
  function walk(dirAbs, dirRel) {
    for (const entry of fs.readdirSync(dirAbs, { withFileTypes: true })) {
      const childAbs = path.join(dirAbs, entry.name);
      const childRel = path.posix.join(dirRel, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === 'tests' || entry.name === 'test_support') continue;
        walk(childAbs, childRel);
      } else if (entry.isFile() && entry.name.endsWith('.rs') && !isTestRustFile(childRel)) {
        files.push({ rel: childRel, source: fs.readFileSync(childAbs, 'utf8') });
      }
    }
  }
  walk(abs, rel);
  if (files.length === 0) {
    throw new Error(
      `${SCRIPT_TAG} consumer directory ${rel} has no production .rs files — `
        + `update CONSUMER_RELS to point at the right module.`,
    );
  }
  return files;
}

/**
 * Parse `pub const NAME: &str = "literal";` definitions out of a naming module.
 * Returns a Map<constName, literal>.
 */
function parseStringConstants(source) {
  const map = new Map();
  const re = /pub\s+const\s+([A-Z][A-Z0-9_]*)\s*:\s*&str\s*=\s*"([^"]*)"\s*;/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    map.set(m[1], m[2]);
  }
  return map;
}

/**
 * Slice the body of `pub const ALL_SYNCABLE_TYPES: &[&str] = &[ ... ];` and
 * resolve every identifier inside to its literal value via `constants`.
 */
function parseAllSyncableTypes(source, constants) {
  const startMatch = source.match(/pub\s+const\s+ALL_SYNCABLE_TYPES\s*:\s*&\[&str\]\s*=\s*&\[/);
  if (!startMatch) {
    throw new Error(`${SCRIPT_TAG} could not locate ALL_SYNCABLE_TYPES in ${ENTITY_TOPOLOGY_REL}`);
  }
  const startIdx = startMatch.index + startMatch[0].length;
  const endIdx = source.indexOf('];', startIdx);
  if (endIdx === -1) {
    throw new Error(`${SCRIPT_TAG} unterminated ALL_SYNCABLE_TYPES slice in ${ENTITY_TOPOLOGY_REL}`);
  }
  const body = source.slice(startIdx, endIdx);

  // Strip line comments inside the slice — explanatory `// Aggregate roots`
  // markers must not be mistaken for identifiers.
  const stripped = body.replace(/\/\/[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');

  const idents = [];
  const idRe = /\b([A-Z][A-Z0-9_]+)\b/g;
  let m;
  while ((m = idRe.exec(stripped)) !== null) {
    idents.push(m[1]);
  }

  const literals = [];
  for (const ident of idents) {
    if (!constants.has(ident)) {
      throw new Error(
        `${SCRIPT_TAG} ALL_SYNCABLE_TYPES references unknown constant ${ident}. ` +
          `Add a string literal definition for it in ${ENTITY_TOPOLOGY_REL} / ${EDGE_NAMING_REL} or remove the entry.`,
      );
    }
    literals.push(constants.get(ident));
  }

  // Sanity: no duplicates expected (Rust unit tests already enforce this,
  // but the verifier is the only check available in pure-JS CI).
  const seen = new Set();
  for (const lit of literals) {
    if (seen.has(lit)) {
      throw new Error(
        `${SCRIPT_TAG} duplicate literal "${lit}" in ALL_SYNCABLE_TYPES — ` +
          `fix the constant definitions in ${ENTITY_TOPOLOGY_REL}.`,
      );
    }
    seen.add(lit);
  }

  return literals;
}

/**
 * Strip Rust line, doc, and block comments from a Rust source string.
 * Block-comment delimiters (slash-star … star-slash) and line-comment
 * markers (slash-slash, slash-slash-slash) often appear in Rust prose
 * around entity-type names — those are explanatory text, not the
 * inline-literal violations this verifier hunts for.
 */
function stripRustComments(source) {
  // Order matters: nested block comments aren't supported by Rust either,
  // so a single non-greedy pass suffices.
  return source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

/**
 * Scan a consumer file for inline subset-LIST violations: Rust
 * array/slice/vec constructions that contain two or more entity-type
 * string literals back-to-back. That pattern is the parallel-inventory
 * smell DC-H8 wants killed.
 *
 * Returns an array of {line, literals, snippet}.
 */
function findInlineLiteralLeaks(rel, source, syncableTypes) {
  const sansComments = stripRustComments(source);
  const offenders = [];
  const typeSet = new Set(syncableTypes);

  // Find every bracketed list — `[ ... ]` after `&`, `vec!`, or as a
  // bare array — and inspect the literals inside. We use a lenient
  // bracket walker that handles nested brackets in items.
  // Track byte offset so we can recover line numbers afterwards.
  const lines = sansComments.split('\n');
  function lineOf(offset) {
    return sansComments.slice(0, offset).split('\n').length;
  }

  for (let i = 0; i < sansComments.length; i++) {
    if (sansComments[i] !== '[') continue;
    // Walk to matching close bracket. Bail out for very long bodies
    // (e.g. a whole match arm) — those are not inventory lists.
    let depth = 1;
    let j = i + 1;
    const max = Math.min(sansComments.length, i + 800);
    while (j < max && depth > 0) {
      const ch = sansComments[j];
      if (ch === '[') depth++;
      else if (ch === ']') depth--;
      if (depth === 0) break;
      j++;
    }
    if (depth !== 0) continue;
    const body = sansComments.slice(i + 1, j);

    // Skip if the body has no comma — single-element lists are not
    // parallel inventories.
    if (!body.includes(',')) continue;

    // Collect string literals inside the body.
    const literals = [];
    const litRe = /"([a-z][a-z0-9_]*)"/g;
    let m;
    while ((m = litRe.exec(body)) !== null) {
      literals.push(m[1]);
    }
    if (literals.length < 2) continue;

    // Filter to only literals that are syncable entity types.
    const matchedTypes = literals.filter((l) => typeSet.has(l));
    if (matchedTypes.length < 2) continue;

    const lineNum = lineOf(i);
    offenders.push({
      file: rel,
      line: lineNum,
      literals: matchedTypes,
      snippet: lines[lineNum - 1]?.trim() ?? '',
    });
    // Skip ahead past this list to avoid double-counting.
    i = j;
  }

  return offenders;
}

function run() {
  const entityConstantsSource = readRel(ENTITY_CONSTANTS_REL);
  const entityTopologySource = readRel(ENTITY_TOPOLOGY_REL);
  const edgeNamingSource = readRel(EDGE_NAMING_REL);
  const constants = new Map([
    ...parseStringConstants(entityConstantsSource),
    ...parseStringConstants(edgeNamingSource),
  ]);
  const syncableTypes = parseAllSyncableTypes(entityTopologySource, constants);

  if (syncableTypes.length === 0) {
    throw new Error(`${SCRIPT_TAG} ALL_SYNCABLE_TYPES is empty — refusing to proceed.`);
  }

  const allOffenders = [];
  let consumerFileCount = 0;
  for (const rel of CONSUMER_RELS) {
    for (const { rel: fileRel, source } of readConsumerSource(rel)) {
      consumerFileCount += 1;
      allOffenders.push(...findInlineLiteralLeaks(fileRel, source, syncableTypes));
    }
  }
  if (allOffenders.length > 0) {
    const lines = allOffenders.map(
      (o) =>
        `  ${o.file}:${o.line} → inline subset list ${JSON.stringify(o.literals)}\n     ${o.snippet}`,
    );
    throw new Error(
      `${SCRIPT_TAG} consumer files contain inline subset lists of syncable-type ` +
        `string literals — replace each entry with the canonical ` +
        `naming::ENTITY_*/EDGE_* constants so a rename in the naming modules cannot drift:\n` +
        lines.join('\n'),
    );
  }

  console.log(
    `${SCRIPT_TAG} ${syncableTypes.length} syncable types; `
      + `${consumerFileCount} consumer file(s) across ${CONSUMER_RELS.length} entry(ies) clean.`,
  );
}

runVerifierCli({
  scriptTag: SCRIPT_TAG,
  successMessage: 'syncable types inventory consistent across naming modules and consumers.',
  run,
});
