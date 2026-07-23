// Contract test (issue #4344): forbid raw `UPDATE tasks ` SQL in
// production Rust outside the canonical write owners.
//
// `CONTRIBUTING.md` and the `lorvex-workflow` crate-level doc declare
// that workflow operations own the SQL mutations every consumer
// surface (Tauri app, CLI, MCP, sync apply) shares. Open-coded
// `UPDATE tasks` on a surface module silently regresses two
// guarantees:
//
//   1. LWW correctness — half the historical raw sites omitted the
//      `version` bump (CLI `remove_task_reminder_with_conn`,
//      app `archive_task` pre-fix); without a fresh stamp, peer
//      caches kept the stale row and the surface's enqueued upsert
//      lex-sorted below any peer's recent write.
//
//   2. Audit funnel — MCP and CLI writes must log to `ai_changelog`,
//      which the workflow's `Mutation<T>` executor wires through the
//      finalizer. A raw UPDATE bypasses the funnel entirely.
//
// The detector grep-scans every production Rust file (cfg(test)
// modules and `tests/` subtrees excluded) and rejects any line
// matching `UPDATE tasks ` unless it lives under one of the
// canonical write-owner path prefixes declared in
// `ALLOWED_PATH_PREFIXES` below. Each prefix carries an inline
// justification so future regroupings (cf. #4409, which moved the
// store-side task repositories from `task_*` siblings into a unified
// `task/` subtree) can refresh the list with a clear contract.
//
// New cross-surface ops belong under `lorvex-workflow/src/task_*.rs`.
// New low-level SQL writers belong under
// `lorvex-store/src/repositories/task/`.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

// Production Rust roots to scan. The detector recurses through each.
// Workflow and store-task-write paths are scanned too — the allowlist
// filter excludes them after the fact so the test still asserts the
// pattern is exercised in tracked code.
const RUST_ROOTS = [
  'app/src-tauri/src',
  'lorvex-cli/src',
  'lorvex-domain/src',
  'lorvex-mcp-derive/src',
  'lorvex-runtime/src',
  'lorvex-store/src',
  'lorvex-sync/src',
  'lorvex-workflow/src',
  'mcp-server/src',
];

// Path prefixes (relative to repoRoot, POSIX separators) where raw
// `UPDATE tasks ` is allowed. Each entry pins a canonical write-owner
// subtree; the comment names the role so a future move can refresh
// the prefix without losing the rationale. When a subtree moves
// (cf. #4409 regrouping `task_write/`, `task_repo/`,
// `task_recurrence_exceptions/`, `task_checklists/` siblings into
// `task/{write,read,recurrence,checklist,dependencies,reminders}/`),
// update the prefix here too — the verifier's string-prefix match
// silently keeps passing on a stale path, but the contract breaks
// the moment a new sibling lands outside the new tree.
const ALLOWED_PATH_PREFIXES = [
  // Canonical cross-surface workflow ops. Owns the
  // version-bump-and-audit-funnel contract every surface delegates
  // into.
  'lorvex-workflow/',
  // Sync apply pipeline. Materializes peer-arrived envelopes by
  // running gated UPDATEs against the local tasks row; bypasses the
  // workflow funnel by design because the changelog entry was
  // produced on the originating device.
  'lorvex-sync/',
  // Store-layer task repository subtree (post-#4409 regrouping).
  // Houses the low-level SQL writers — `task/write/` (column-set
  // updates), `task/recurrence/` (exception list maintenance),
  // `task/checklist/` (promote-to-task body rewrites), and any
  // future sibling — that workflow ops delegate into.
  'lorvex-store/src/repositories/task/',
  // Provider / file-based import path. Materializes peer-arrived
  // task rows during restore; a sibling of the sync-apply pipeline
  // above and similarly funnel-exempt because the changelog entry
  // travels with the imported payload.
  'lorvex-store/src/import/apply/upserts/tasks',
];

// Files where every `UPDATE tasks ` occurrence is inside an item
// individually gated by `#[cfg(test)]` (and therefore is dead in
// production). The detector below only auto-excludes `#[cfg(test)]
// mod tests { ... }` blocks; module-files whose entire production
// surface was removed and replaced with file-wide `#[cfg(test)]`
// item gates need an explicit allowlist entry with a justification.
const CFG_TEST_ONLY_FILES = [
  // The renderer-facing `clear_all_raw_input` command was removed in
  // #2940-H1; the surviving `clear_all_raw_input_with_conn` helper is
  // now `#[cfg(test)]`-only test scaffold pinning the
  // rollback-on-enqueue-failure regression test. See #4344.
  'app/src-tauri/src/commands/tasks/privacy/mod.rs',
];

function walkRustFiles(absoluteRoot) {
  if (!fs.existsSync(absoluteRoot)) return [];
  const results = [];
  for (const entry of fs.readdirSync(absoluteRoot, { withFileTypes: true })) {
    const full = path.join(absoluteRoot, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'target' || entry.name === '.git' || entry.name === 'tests') {
        continue;
      }
      results.push(...walkRustFiles(full));
    } else if (entry.isFile() && entry.name.endsWith('.rs')) {
      if (entry.name === 'tests.rs' && isCfgTestModuleFile(full)) continue;
      results.push(full);
    }
  }
  return results;
}

function isCfgTestModuleFile(absolutePath) {
  const parentDir = path.dirname(absolutePath);
  const parentName = path.basename(parentDir);
  const candidates = [
    path.join(parentDir, 'mod.rs'),
    path.join(path.dirname(parentDir), `${parentName}.rs`),
  ];
  return candidates.some((candidate) => {
    if (!fs.existsSync(candidate)) return false;
    const source = fs.readFileSync(candidate, 'utf8');
    return /#\[cfg\([^\]]*\btest\b[^\]]*\)\]\s*(?:#\[[^\]]+\]\s*)*mod\s+tests\s*;/m.test(source);
  });
}

function relativePosix(absolutePath) {
  return path.relative(repoRoot, absolutePath).split(path.sep).join('/');
}

function isAllowedPath(relativePath) {
  return ALLOWED_PATH_PREFIXES.some((prefix) => relativePath.startsWith(prefix));
}

function isCfgTestOnlyFile(relativePath) {
  return CFG_TEST_ONLY_FILES.includes(relativePath);
}

/**
 * Scan a Rust source file for `UPDATE tasks ` (note the trailing
 * space — `UPDATE task_dependencies`, `UPDATE task_reminders`, etc.
 * are sibling tables with their own SQL contracts and must not be
 * caught here).
 *
 * Lines inside `#[cfg(test)] mod tests { ... }` blocks are excluded
 * by walking brace depth from the test-module entry. Commented-out
 * occurrences and string-literal contracts inside the verifier
 * itself are excluded by a simple `//`-prefix check.
 */
function scanFile(content, relativePath) {
  const findings = [];
  const lines = content.split('\n');
  let inTestBlock = 0;
  let testBraceBudget = null;

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const stripped = raw.trim();

    if (testBraceBudget != null) {
      for (const ch of raw) {
        if (ch === '{') inTestBlock++;
        else if (ch === '}') inTestBlock--;
      }
      if (inTestBlock <= testBraceBudget) {
        testBraceBudget = null;
        inTestBlock = 0;
      }
    }

    if (/#\[cfg\(test\)\]/.test(raw) && testBraceBudget == null) {
      for (let j = i; j < Math.min(i + 3, lines.length); j++) {
        if (/\bmod\s+\w+\s*\{/.test(lines[j] ?? '')) {
          testBraceBudget = inTestBlock;
          for (const ch of lines[j]) {
            if (ch === '{') inTestBlock++;
            else if (ch === '}') inTestBlock--;
          }
          break;
        }
      }
    }

    if (testBraceBudget != null && inTestBlock > testBraceBudget) continue;
    if (stripped.startsWith('//') || stripped.startsWith('*')) continue;

    if (/\bUPDATE\s+tasks\s/i.test(raw)) {
      findings.push({
        file: relativePath,
        line: i + 1,
        text: raw.trim(),
      });
    }
  }
  return findings;
}

test('production Rust must route `UPDATE tasks ` SQL through lorvex-workflow (or lorvex-sync apply, or lorvex-store task repos)', () => {
  const findings = [];
  for (const root of RUST_ROOTS) {
    const absoluteRoot = path.join(repoRoot, root);
    for (const file of walkRustFiles(absoluteRoot)) {
      const relative = relativePosix(file);
      if (isAllowedPath(relative)) continue;
      if (isCfgTestOnlyFile(relative)) continue;
      const content = fs.readFileSync(file, 'utf8');
      findings.push(...scanFile(content, relative));
    }
  }

  if (findings.length > 0) {
    const detail = findings.map((f) => `  ${f.file}:${f.line}  ${f.text}`).join('\n');
    assert.fail(
      `Found ${findings.length} raw \`UPDATE tasks \` occurrence(s) outside the canonical write owners.\n` +
        `Per issue #4344 every task UPDATE must go through a \`lorvex-workflow\` op so the version\n` +
        `bump + audit funnel are guaranteed. Migrate the SQL into \`lorvex-workflow/src/task_*.rs\`\n` +
        `(or the sync-apply pipeline, when materializing a peer envelope), and call it from the surface.\n\n` +
        detail,
    );
  }
});

test('no_direct_task_updates detector flags a synthetic surface-level UPDATE', () => {
  const synthetic = `
pub fn bad(conn: &Connection, id: &str, now: &str) {
    conn.execute(
        "UPDATE tasks SET status = 'cancelled', updated_at = ?1 WHERE id = ?2",
        params![now, id],
    ).unwrap();
}
`;
  const findings = scanFile(synthetic, 'app/src-tauri/src/example.rs');
  assert.equal(findings.length, 1, 'detector should flag the forbidden raw UPDATE tasks');
});

test('no_direct_task_updates detector ignores sibling-table UPDATEs', () => {
  const synthetic = `
pub fn ok(conn: &Connection) {
    conn.execute("UPDATE task_reminders SET cancelled_at = NULL WHERE id = ?1", [id]).unwrap();
    conn.execute("UPDATE task_dependencies SET version = ?1 WHERE task_id = ?2", [v, t]).unwrap();
    conn.execute("UPDATE task_tags SET version = ?1 WHERE task_id = ?2", [v, t]).unwrap();
}
`;
  const findings = scanFile(synthetic, 'app/src-tauri/src/example.rs');
  assert.equal(findings.length, 0, 'detector must NOT flag sibling-table UPDATEs');
});

test('no_direct_task_updates detector ignores cfg(test) helpers', () => {
  const synthetic = `
pub fn produces(conn: &Connection) {}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fixture() {
        let conn = open();
        conn.execute("UPDATE tasks SET archived_at = ?1 WHERE id = ?2", [now, id]).unwrap();
    }
}
`;
  const findings = scanFile(synthetic, 'app/src-tauri/src/example.rs');
  assert.equal(findings.length, 0, 'detector must NOT flag UPDATE tasks inside cfg(test) modules');
});
