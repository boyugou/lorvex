#!/usr/bin/env node
/**
 * Audit #2610: lock-file check for `lorvex-store/src/schema/NNN_*.sql`.
 *
 * The migration framework records each file's sha256 in the
 * `schema_migrations` table the first time it runs. A later binary
 * that sees a different sha returns `ChecksumMismatch` and refuses to
 * start — the user is locked out of their data with no in-app
 * remediation. This has happened three times (b4d67a32, 361878fe,
 * 77223fba) and the latest was live-install-bricking until the revert
 * in #2605.
 *
 * This verifier locks the sha256 of every migration file in
 * `lorvex-store/src/schema/checksums.lock` (JSON map version → sha).
 * A drift FAILS CI and tells the developer to either intentionally
 * reseed the lock for the consolidated schema, OR revert the change.
 *
 * Run locally:
 *   node scripts/verify/migration_checksums.mjs          (verify)
 *   node scripts/verify/migration_checksums.mjs --seed   (regenerate
 *                                                         the lock
 *                                                         after an
 *                                                         intentional
 *                                                         schema edit)
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { assertContract, resolveRepoRootFromMeta, runVerifierCli } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[migration_checksums]';
const REPO_ROOT = resolveRepoRootFromMeta(import.meta.url);
const SCHEMA_DIR = path.join(REPO_ROOT, 'lorvex-store/src/schema');
const LOCK_PATH = path.join(SCHEMA_DIR, 'checksums.lock');
const MIGRATION_RE = /^(\d{3})_[A-Za-z0-9_]+\.sql$/;

/**
 * Normalize a migration's SQL text for hashing.
 *
 * MUST stay byte-for-byte identical with the runtime implementation in
 * `lorvex-store/src/migration/checksum/mod.rs::sha256_hex`. If the two
 * ever diverge, the runtime can trip `ChecksumMismatch` on a row this
 * verifier just blessed (audit #2972 — a Windows clone with
 * `core.autocrlf=true` editing the file would make the verifier pass
 * while the runtime rejects). Steps, in order:
 *   1. strip a UTF-8 BOM if present;
 *   2. replace CRLF with LF;
 *   3. strip SQL comments AND drop any line that becomes whitespace-
 *      only as a result, AND trim trailing whitespace before an inline
 *      comment. This is what makes the "comment-only edits don't
 *      change the hash" invariant actually hold: reflowing a 5-line
 *      comment block into 7 lines, or moving an inline comment without
 *      changing the surrounding code, both produce the same digest.
 *      See issue #3274 for the regression this replaces.
 *   4. trim leading/trailing whitespace.
 *
 * Interior whitespace inside non-comment SQL is intentionally preserved
 * so semantic edits cannot slip past the lock by reformatting alone.
 */
export function normalizeMigrationSql(rawText) {
  let normalized = rawText;
  if (normalized.charCodeAt(0) === 0xfeff) {
    normalized = normalized.slice(1);
  }
  normalized = normalized.replace(/\r\n/g, '\n');
  normalized = stripSqlComments(normalized);
  return normalized.trim();
}

/**
 * Strip SQL comments (`-- line` and `/* block *\/`) while preserving
 * string literals and identifiers. Mirrors
 * `lorvex-store/src/migration/checksum/mod.rs::strip_sql_comments`
 * byte-for-byte.
 *
 * Per-line buffering: each line accumulates into `pending` until a
 * newline (outside any literal) flushes it. A line that contains no
 * non-whitespace content after comment removal is dropped entirely —
 * including its trailing newline — so a 5-line comment block and a
 * 7-line comment block reduce to the same output. Inline comments
 * also trim the trailing whitespace they leave behind on the
 * surviving line, so `"X; -- inline\n"` and `"X;\n"` hash equal.
 *
 * Quoted runs (single quotes for string literals, double quotes for
 * identifiers) pass through verbatim, including embedded newlines and
 * embedded `--` / `/*` markers (those are NOT comments at the SQL
 * parser level). SQLite-style escaped quotes (`''` / `""`) keep the
 * quoted run open. Block comments do not nest in SQLite; an
 * unterminated block runs to end-of-input.
 */
function stripSqlComments(sql) {
  // Array.from gives full Unicode code points (handles surrogate pairs
  // correctly), matching the Rust implementation's whole-char copy in
  // multi-byte UTF-8 sequences inside literals.
  const chars = Array.from(sql);
  let out = '';
  let pending = '';
  let pendingHasContent = false;
  let i = 0;

  const trimPendingEnd = () => {
    pending = pending.replace(/\s+$/, '');
    if (pending.length === 0) {
      pendingHasContent = false;
    }
  };

  while (i < chars.length) {
    const c = chars[i];

    if (c === '\n') {
      if (pendingHasContent) {
        out += pending;
        out += '\n';
      }
      pending = '';
      pendingHasContent = false;
      i += 1;
      continue;
    }

    if (c === "'") {
      pending += "'";
      pendingHasContent = true;
      i += 1;
      while (i < chars.length) {
        if (chars[i] === "'") {
          pending += "'";
          i += 1;
          if (i < chars.length && chars[i] === "'") {
            pending += "'";
            i += 1;
            continue;
          }
          break;
        }
        // Embedded characters (including \n) copy verbatim into pending
        // — \n inside a literal must NOT trigger the outer-loop flush,
        // and that's handled implicitly because we don't return to the
        // outer match until the closing quote.
        pending += chars[i];
        i += 1;
      }
      continue;
    }

    if (c === '"') {
      pending += '"';
      pendingHasContent = true;
      i += 1;
      while (i < chars.length) {
        if (chars[i] === '"') {
          pending += '"';
          i += 1;
          if (i < chars.length && chars[i] === '"') {
            pending += '"';
            i += 1;
            continue;
          }
          break;
        }
        pending += chars[i];
        i += 1;
      }
      continue;
    }

    if (c === '-' && i + 1 < chars.length && chars[i + 1] === '-') {
      // Line comment: trim trailing whitespace pre-comment so an
      // inline comment doesn't leak `"X;   "` into the hash. The
      // newline (if any) is left for the outer loop; if the line
      // ends up whitespace-only it will be dropped there.
      trimPendingEnd();
      i += 2;
      while (i < chars.length && chars[i] !== '\n') {
        i += 1;
      }
      continue;
    }

    if (c === '/' && i + 1 < chars.length && chars[i + 1] === '*') {
      // Block comment — same trim rule. Block comments may span
      // multiple lines; we consume the whole span, so any newlines
      // inside the comment vanish along with the rest.
      trimPendingEnd();
      i += 2;
      while (i + 1 < chars.length && !(chars[i] === '*' && chars[i + 1] === '/')) {
        i += 1;
      }
      if (i + 1 < chars.length) {
        i += 2;
      } else {
        i = chars.length;
      }
      continue;
    }

    pending += c;
    if (c.trim() !== '') {
      pendingHasContent = true;
    }
    i += 1;
  }

  if (pendingHasContent) {
    out += pending;
  }
  return out;
}

/**
 * Hash a migration's SQL text using the same algorithm the Rust runtime
 * uses (see `normalizeMigrationSql` for the contract). Exported for the
 * cross-language regression test that pairs this verifier with
 * `lorvex-store::migration::checksum::sha256_hex`.
 */
export function sha256MigrationHex(rawText) {
  const normalized = normalizeMigrationSql(rawText);
  return crypto.createHash('sha256').update(normalized, 'utf8').digest('hex');
}

function listMigrations() {
  const entries = fs.readdirSync(SCHEMA_DIR);
  const rows = [];
  for (const name of entries) {
    const match = name.match(MIGRATION_RE);
    if (!match) continue;
    const version = Number(match[1]);
    const text = fs.readFileSync(path.join(SCHEMA_DIR, name), 'utf8');
    rows.push({ version, name, sha: sha256MigrationHex(text) });
  }
  rows.sort((a, b) => a.version - b.version);
  return rows;
}

function readLock() {
  if (!fs.existsSync(LOCK_PATH)) {
    return null;
  }
  const raw = fs.readFileSync(LOCK_PATH, 'utf8');
  try {
    return JSON.parse(raw);
  } catch (err) {
    throw new Error(`${SCRIPT_TAG} corrupt lock file at ${LOCK_PATH}: ${err.message}`);
  }
}

function writeLock(entries) {
  const obj = {};
  for (const row of entries) {
    obj[String(row.version).padStart(3, '0')] = { name: row.name, sha256: row.sha };
  }
  fs.writeFileSync(LOCK_PATH, `${JSON.stringify(obj, null, 2)}\n`);
}

function seed() {
  const rows = listMigrations();
  writeLock(rows);
  console.log(`${SCRIPT_TAG} Wrote ${LOCK_PATH} with ${rows.length} entries.`);
}

function verify() {
  const rows = listMigrations();
  const lock = readLock();
  if (lock == null) {
    throw new Error(
      `${SCRIPT_TAG} lock file missing at ${LOCK_PATH}. Run \`node scripts/verify/migration_checksums.mjs --seed\` to initialize, then review the resulting file.`,
    );
  }
  const drift = [];
  const seenKeys = new Set();
  for (const row of rows) {
    const key = String(row.version).padStart(3, '0');
    seenKeys.add(key);
    const recorded = lock[key];
    if (!recorded) {
      drift.push(
        `new migration ${row.name} not in lock — this repo uses a consolidated schema; review whether the new file is intentional, then run \`node scripts/verify/migration_checksums.mjs --seed\` only for an approved schema-registry change.`,
      );
      continue;
    }
    if (recorded.name !== row.name) {
      drift.push(
        `migration ${key} renamed from ${recorded.name} to ${row.name} — rename is forbidden on a shipped migration (breaks ChecksumMismatch runtime guard).`,
      );
    }
    if (recorded.sha256 !== row.sha) {
      drift.push(
        `migration ${row.name} sha256 changed (locked: ${recorded.sha256.slice(0, 16)}…, actual: ${row.sha.slice(0, 16)}…). If this is an intentional consolidated-schema edit, run \`node scripts/verify/migration_checksums.mjs --seed\`; otherwise revert the migration edit. See #2605.`,
      );
    }
  }
  for (const key of Object.keys(lock)) {
    if (!seenKeys.has(key)) {
      drift.push(`migration ${key} is in lock but missing on disk (${lock[key].name}).`);
    }
  }
  assertContract(drift.length === 0, SCRIPT_TAG, drift.map((d) => `\n  - ${d}`).join(''));
}

// Only run the CLI when this file is the process entry point. The
// helper functions above are imported by the parity regression test
// (`scripts/tests/runtime/migration_checksum_parity.test.mjs`); without
// this guard the test harness would re-execute the verifier on every
// import and process.exit(1) on any drift would kill the test runner.
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'OK: migration files match checksums.lock',
    run: () => {
      const args = new Set(process.argv.slice(2));
      if (args.has('--seed')) {
        seed();
      } else {
        verify();
      }
    },
  });
}
