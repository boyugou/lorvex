import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

/**
 * `shared/src/types.ts` splits the canonical sync-type vocabulary into
 * two narrow tuples — `SYNC_AGGREGATE_TYPES` (aggregate roots +
 * independent children + content-addressed assets + audit stream) and
 * `SYNC_EDGE_TYPES` (relation edges) — that mirror the Rust split in
 * `lorvex-domain/src/naming/`: `ALL_ENTITY_TYPES` and `ALL_EDGE_TYPES`.
 * `SYNC_ENTITY_TYPES` is the spread-derived union of both, mirroring
 * `naming::ALL_SYNCABLE_TYPES`.
 *
 * Pre-fix the invariant ("this union must mirror the Rust constants")
 * was a comment with no automated enforcement — the TS list could
 * silently drift past the Rust source of truth (and had: `memory_
 * revision` was missing, and `calendar_subscription` / `blob_asset` /
 * `ai_changelog` were out of position before the audit fix). A drift
 * produces a silently-degraded discriminated union: peers emit a kind
 * the TS side accepts as plain `string`, sliding past every exhaustive
 * switch without a compile-time signal.
 *
 * This contract parses both sides from source (no Rust ↔ TS shared
 * runtime) and asserts each TS tuple equals its Rust counterpart
 * exactly, including order.
 */

const TS_TYPES_PATH = path.join(repoRoot, 'shared/src/types.ts');
// naming/entity/mod.rs has been split into mod, constants, kind, error,
// blob_reference, topology (+ tests). The wire-format `ENTITY_*` strings and
// `ALL_ENTITY_TYPES` slice now live in constants.rs.
const RUST_ENTITY_PATH = path.join(repoRoot, 'lorvex-domain/src/naming/entity/constants.rs');
const RUST_EDGE_PATH = path.join(repoRoot, 'lorvex-domain/src/naming/edge.rs');

function read(absolutePath) {
  return fs.readFileSync(absolutePath, 'utf8');
}

/**
 * Pull a `pub const ENTITY_X: &str = "value";` table from a Rust
 * source file into a `name -> value` map. Restricted to `pub const`
 * so private constants (or unrelated `const` tables) cannot leak
 * into the parity check.
 */
function parseRustStringConsts(source) {
  const consts = new Map();
  const re = /pub const ([A-Z_][A-Z0-9_]*)\s*:\s*&str\s*=\s*"([^"]*)"\s*;/g;
  for (const match of source.matchAll(re)) {
    consts.set(match[1], match[2]);
  }
  return consts;
}

/**
 * Pull the body of `pub const NAME: &[&str] = &[ X, Y, Z ];` from a
 * Rust source and return the ordered list of identifiers (X, Y, Z).
 * Whitespace and trailing commas are tolerated. Inline `//` comments
 * and `/// `-style rustdoc on the constant declaration itself are
 * ignored.
 */
function parseRustStrSliceConst(source, constName) {
  const headerRe = new RegExp(
    `pub const ${constName}\\s*:\\s*&\\[&str\\]\\s*=\\s*&\\[([\\s\\S]*?)\\];`,
  );
  const headerMatch = source.match(headerRe);
  assert.ok(headerMatch, `expected to find \`pub const ${constName}: &[&str] = &[…]\` in source`);
  const body = headerMatch[1]
    // Drop line comments inside the array literal.
    .replace(/\/\/[^\n]*\n/g, '\n');
  return body
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);
}

/**
 * Pull the literal entries from a `export const NAME = [ 'x', 'y',
 * 'z' ] as const;` declaration in a TS source. Inline `//` comments
 * are ignored.
 */
function parseTsConstStringArray(source, constName) {
  const headerRe = new RegExp(
    `export const ${constName}\\s*=\\s*\\[([\\s\\S]*?)\\]\\s*as const;`,
  );
  const headerMatch = source.match(headerRe);
  assert.ok(headerMatch, `expected to find \`export const ${constName} = […] as const;\` in source`);
  const body = headerMatch[1].replace(/\/\/[^\n]*\n/g, '\n');
  const out = [];
  const re = /'([^']*)'/g;
  for (const match of body.matchAll(re)) {
    out.push(match[1]);
  }
  return out;
}

function resolveRustIdents(idents, constValues) {
  return idents.map((ident) => {
    const value = constValues.get(ident);
    assert.ok(
      value !== undefined,
      `Rust ${ident} referenced from a slice constant but no \`pub const ${ident}: &str = "…";\` was found`,
    );
    return value;
  });
}

test('SYNC_AGGREGATE_TYPES mirrors `ALL_ENTITY_TYPES` exactly', () => {
  const entitySource = read(RUST_ENTITY_PATH);
  const edgeSource = read(RUST_EDGE_PATH);
  const tsSource = read(TS_TYPES_PATH);

  const constValues = new Map([
    ...parseRustStringConsts(entitySource).entries(),
    ...parseRustStringConsts(edgeSource).entries(),
  ]);

  const expected = resolveRustIdents(
    parseRustStrSliceConst(entitySource, 'ALL_ENTITY_TYPES'),
    constValues,
  );
  const actual = parseTsConstStringArray(tsSource, 'SYNC_AGGREGATE_TYPES');

  assert.deepEqual(
    actual,
    expected,
    [
      'shared/src/types.ts SYNC_AGGREGATE_TYPES drifted from Rust naming::ALL_ENTITY_TYPES.',
      `Expected (Rust): ${JSON.stringify(expected)}`,
      `Actual (TS):     ${JSON.stringify(actual)}`,
      'A peer-emitted envelope for a missing kind decodes to plain string and bypasses the discriminated union — re-sync the TS list with the Rust constants in the same change.',
    ].join('\n  '),
  );
});

test('SYNC_EDGE_TYPES mirrors `ALL_EDGE_TYPES` exactly', () => {
  const entitySource = read(RUST_ENTITY_PATH);
  const edgeSource = read(RUST_EDGE_PATH);
  const tsSource = read(TS_TYPES_PATH);

  const constValues = new Map([
    ...parseRustStringConsts(entitySource).entries(),
    ...parseRustStringConsts(edgeSource).entries(),
  ]);

  const expected = resolveRustIdents(
    parseRustStrSliceConst(edgeSource, 'ALL_EDGE_TYPES'),
    constValues,
  );
  const actual = parseTsConstStringArray(tsSource, 'SYNC_EDGE_TYPES');

  assert.deepEqual(
    actual,
    expected,
    [
      'shared/src/types.ts SYNC_EDGE_TYPES drifted from Rust naming::edge::ALL_EDGE_TYPES.',
      `Expected (Rust): ${JSON.stringify(expected)}`,
      `Actual (TS):     ${JSON.stringify(actual)}`,
      'A peer-emitted envelope for a missing edge kind decodes to plain string and bypasses the discriminated union — re-sync the TS list with the Rust constants in the same change.',
    ].join('\n  '),
  );
});

test('SYNC_AGGREGATE_TYPES + SYNC_EDGE_TYPES has no duplicate entries', () => {
  const tsSource = read(TS_TYPES_PATH);
  const aggregates = parseTsConstStringArray(tsSource, 'SYNC_AGGREGATE_TYPES');
  const edges = parseTsConstStringArray(tsSource, 'SYNC_EDGE_TYPES');
  const all = [...aggregates, ...edges];
  const seen = new Set();
  const dups = [];
  for (const value of all) {
    if (seen.has(value)) {
      dups.push(value);
    }
    seen.add(value);
  }
  assert.deepEqual(
    dups,
    [],
    `SYNC_AGGREGATE_TYPES/SYNC_EDGE_TYPES contains duplicate entries: ${JSON.stringify(dups)}`,
  );
});
