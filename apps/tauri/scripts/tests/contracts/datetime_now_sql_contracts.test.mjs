// Contract test: forbid `datetime('now', ...)` in production Rust SQL.
//
// SQLite's `datetime('now', ...)` returns a SPACE-separated timestamp
// (`2026-04-10 12:34:56`) while the canonical Lorvex write path uses
// `sync_timestamp_now()` which emits RFC 3339 T-separated milliseconds
// (`2026-04-10T12:34:56.789Z`). When those two formats are compared
// via SQLite string comparison (which is what `col < datetime('now')`
// and `col > datetime('now')` do for TEXT columns), the `T (0x54)` vs
// ` (0x20)` difference at position 10 flips the comparison for rows
// whose date prefix matches the cutoff. The row appears "in the
// future" relative to the cutoff even though it's semantically older.
//
// This class of bug has shipped twice:
//   1. R5 — `run_data_retention_cleanup` silently kept rows past the
//      retention window because cleanup never deleted anything.
//   2. R11 — `provider_stale_scopes` silently treated stale calendar
//      scopes as fresh, skipping background refresh for up to 24h.
//
// Both fixes were identical: switch to
// `strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ...)`. This contract exists
// so the pattern cannot regress a third time — production SQL is
// grep-scanned and any `datetime('now'` occurrence outside of a
// `#[cfg(test)]` block or a test helper is rejected at CI time.
//
// Allowlist: any legitimate use case (e.g., computing a display-only
// timestamp that's never compared to a stored column) can be opted
// in by adding the containing line to ALLOWED_MATCHES with a
// justification comment.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

// Production Rust roots to scan. Test helpers live under `/tests/`
// subdirectories or inside `#[cfg(test)] mod tests` blocks — those
// are excluded by the line filter below.
const RUST_ROOTS = [
  'app/src-tauri/src',
  'lorvex-store/src',
  'lorvex-sync/src',
  'lorvex-domain/src',
  'lorvex-runtime/src',
  'mcp-server/src',
];

// Lines that match this regex are accepted even though they contain
// `datetime('now'`. Add a one-line justification for each entry.
const ALLOWED_MATCHES = [
  // (none — canonical form is strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ...))
];

function walkRustFiles(absoluteRoot) {
  if (!fs.existsSync(absoluteRoot)) return [];
  const results = [];
  for (const entry of fs.readdirSync(absoluteRoot, { withFileTypes: true })) {
    const full = path.join(absoluteRoot, entry.name);
    if (entry.isDirectory()) {
      // Skip target/, git dirs, and any explicit tests subdir that
      // contains integration helpers.
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
    return /#\[cfg\([^\]]*\btest\b[^\]]*\)\]\s*(?:#\[[^\]]+\]\s*)*mod\s+tests\s*;/m.test(
      source,
    );
  });
}

/**
 * Scan a Rust source file and return the byte offsets of every line
 * that mentions `datetime('now'` in a context that is NOT inside a
 * `#[cfg(test)] mod tests { ... }` block.
 *
 * The detector walks brace depth from each `#[cfg(test)] mod` entry
 * so it knows when we've exited the test module. This is more robust
 * than a simple "line contains #[cfg(test)]" check because test
 * helpers inside the module can span many lines.
 */
function scanFileForForbiddenDatetime(content, relativePath) {
  const findings = [];
  const lines = content.split('\n');
  let inTestBlock = 0; // brace-depth counter (0 = not in a test block)
  let testBraceBudget = null; // brace depth at the `mod tests {` line

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const stripped = raw.trim();

    // Count braces only on lines that don't contain a comment to
    // the start — a simple heuristic is fine because we only need
    // to track the test-module boundary.
    if (testBraceBudget != null) {
      for (const ch of raw) {
        if (ch === '{') inTestBlock++;
        else if (ch === '}') inTestBlock--;
      }
      if (inTestBlock <= testBraceBudget) {
        // Re-entered the outer scope; the test block is closed.
        testBraceBudget = null;
        inTestBlock = 0;
      }
    }

    // Detect entry into `#[cfg(test)] mod tests {`. We also accept
    // `#[cfg(test)]\nmod tests {` (attribute on previous line).
    const isTestModEntry =
      /^\s*#\[cfg\(test\)\]\s*$/.test(lines[i] ?? '') ||
      /#\[cfg\(test\)\]/.test(lines[i] ?? '');

    if (isTestModEntry && testBraceBudget == null) {
      // Look ahead for `mod tests` within a couple lines.
      for (let j = i; j < Math.min(i + 3, lines.length); j++) {
        if (/\bmod\s+\w+\s*\{/.test(lines[j] ?? '')) {
          // Start a test block at whatever the brace depth is now.
          testBraceBudget = inTestBlock;
          // Count the `{` on this line into the depth.
          for (const ch of lines[j]) {
            if (ch === '{') inTestBlock++;
            else if (ch === '}') inTestBlock--;
          }
          break;
        }
      }
    }

    // Skip if we're currently inside a test module.
    if (testBraceBudget != null && inTestBlock > testBraceBudget) {
      continue;
    }

    // Skip commented-out lines (comment chars at start of trimmed
    // line). A commented example of the forbidden form is fine.
    if (stripped.startsWith('//') || stripped.startsWith('*')) {
      continue;
    }

    // Look for the forbidden pattern.
    if (/datetime\s*\(\s*'now'/.test(raw)) {
      if (ALLOWED_MATCHES.some((pattern) => pattern.test(raw))) {
        continue;
      }
      findings.push({
        file: relativePath,
        line: i + 1,
        text: raw.trim(),
      });
    }
  }
  return findings;
}

test('production Rust SQL must not use datetime(\'now\', ...) — use strftime(\'%Y-%m-%dT%H:%M:%fZ\', \'now\', ...) instead', () => {
  const findings = [];
  for (const root of RUST_ROOTS) {
    const absoluteRoot = path.join(repoRoot, root);
    for (const file of walkRustFiles(absoluteRoot)) {
      const content = fs.readFileSync(file, 'utf8');
      const relative = path.relative(repoRoot, file);
      findings.push(...scanFileForForbiddenDatetime(content, relative));
    }
  }

  if (findings.length > 0) {
    const detail = findings
      .map((f) => `  ${f.file}:${f.line}  ${f.text}`)
      .join('\n');
    assert.fail(
      `Found ${findings.length} forbidden datetime('now', ...) usage(s) in production Rust SQL.\n` +
        `This pattern returns a SPACE-separated timestamp that cannot be lex-compared\n` +
        `against RFC 3339 T-separated columns (see R5 retention fix, R11 provider refresh fix).\n` +
        `Switch to strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ...) so both sides share the T separator.\n\n` +
        detail,
    );
  }
});

test('datetime_now_sql_contracts rejects a minimal synthetic bad example', () => {
  const synthetic = `
pub fn example(conn: &Connection) {
    conn.execute(
        "DELETE FROM foo WHERE created_at < datetime('now', '-24 hours')",
        [],
    );
}
`;
  const findings = scanFileForForbiddenDatetime(synthetic, 'synthetic.rs');
  assert.equal(
    findings.length,
    1,
    'detector should flag the forbidden pattern in a synthetic bad example',
  );
});

test('datetime_now_sql_contracts accepts the canonical strftime form', () => {
  const synthetic = `
pub fn example(conn: &Connection) {
    conn.execute(
        "DELETE FROM foo WHERE created_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-24 hours')",
        [],
    );
}
`;
  const findings = scanFileForForbiddenDatetime(synthetic, 'synthetic.rs');
  assert.equal(
    findings.length,
    0,
    'detector must NOT flag the canonical strftime form',
  );
});

test('datetime_now_sql_contracts ignores commented-out example', () => {
  const synthetic = `
// Previously: datetime('now', '-7 days')
// Now using strftime for consistency.
pub fn example() {}
`;
  const findings = scanFileForForbiddenDatetime(synthetic, 'synthetic.rs');
  assert.equal(findings.length, 0, 'detector must ignore comments');
});

// ---------------------------------------------------------------------------
// Chrono format drift: keep canonical timestamp formatting centralized
// ---------------------------------------------------------------------------
// R11/R12/R13 each fixed timestamp format drift where chrono produced a
// string that lex-sorted incorrectly against canonical
// `sync_timestamp_now()` columns. The canonical writer is
// `lorvex_domain::sync_timestamp_now()` or
// `lorvex_domain::format_sync_timestamp`. This sweep rejects ad hoc
// sync-storage `.format("%Y-%m-%dT%H:%M:%S%.3fZ")`, direct
// `.to_rfc3339_opts(...)`, and bare `.to_rfc3339()` calls in production Rust
// so stored timestamp suffix rules remain a single-file domain decision.

const ALLOWED_CHRONO_FORMAT_MATCHES = [];

function isAllowedChronoFormat(relativePath, raw) {
  // The canonical timestamp formatter lives in the time/ folder of
  // lorvex-domain. Both the consolidated time.rs (legacy) and the
  // post-split time/sync_timestamp.rs are allowed to call into chrono's
  // canonical RFC3339 helper directly — this is the very file every
  // other crate is required to route through.
  if (
    (relativePath === 'lorvex-domain/src/time.rs' ||
      relativePath === 'lorvex-domain/src/time/sync_timestamp.rs') &&
    /\.to_rfc3339_opts\(/.test(raw)
  ) {
    return true;
  }
  return ALLOWED_CHRONO_FORMAT_MATCHES.some(
    (entry) => entry.file === relativePath && entry.pattern.test(raw),
  );
}

function scanFileForForbiddenChronoFormat(content, relativePath) {
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
    if (isAllowedChronoFormat(relativePath, raw)) continue;

    // Forbidden: ad hoc format that bypasses the domain helper.
    if (/\.format\(\s*"%Y-%m-%dT%H:%M:%S%\.3fZ"/.test(raw)) {
      findings.push({
        file: relativePath,
        line: i + 1,
        text: raw.trim(),
        reason: 'ad hoc timestamp format bypasses lorvex_domain::format_sync_timestamp',
      });
    }

    if (/\.to_rfc3339_opts\(/.test(raw)) {
      findings.push({
        file: relativePath,
        line: i + 1,
        text: raw.trim(),
        reason: 'direct .to_rfc3339_opts(...) bypasses lorvex_domain timestamp helpers',
      });
    }

    // Forbidden: bare `.to_rfc3339()` (without `_opts`). This method
    // produces a `+00:00` UTC offset suffix instead of `Z`. Mixing
    // `+00:00` and `Z` timestamps in the same column breaks lex
    // comparison regardless of direction. The canonical form is
    // `sync_timestamp_now()` or `format_sync_timestamp`.
    // R12 fixed 8 instances; R22 found 4 more that slipped through
    // because this pattern wasn't in the contract test.
    if (/\.to_rfc3339\(\)/.test(raw)) {
      findings.push({
        file: relativePath,
        line: i + 1,
        text: raw.trim(),
        reason: 'bare .to_rfc3339() produces +00:00 suffix instead of Z — use sync_timestamp_now() or format_sync_timestamp',
      });
    }
  }
  return findings;
}

test('production Rust must route canonical timestamp formatting through lorvex-domain helpers', () => {
  const findings = [];
  for (const root of RUST_ROOTS) {
    const absoluteRoot = path.join(repoRoot, root);
    for (const file of walkRustFiles(absoluteRoot)) {
      const content = fs.readFileSync(file, 'utf8');
      const relative = path.relative(repoRoot, file);
      findings.push(...scanFileForForbiddenChronoFormat(content, relative));
    }
  }

  if (findings.length > 0) {
    const detail = findings
      .map((f) => `  ${f.file}:${f.line}  ${f.text}`)
      .join('\n');
    assert.fail(
      `Found ${findings.length} direct timestamp formatter usage(s) in production Rust.\n` +
        `Canonical timestamp precision and suffix rules must live in lorvex-domain/src/time.rs.\n` +
        `Use lorvex_domain::sync_timestamp_now() or lorvex_domain::format_sync_timestamp(...) instead.\n\n` +
        detail,
    );
  }
});

test('chrono format contract rejects an ad hoc synthetic example', () => {
  const synthetic = `
pub fn bad() {
    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string();
    use_now(now);
}
`;
  const findings = scanFileForForbiddenChronoFormat(synthetic, 'synthetic.rs');
  assert.equal(
    findings.length,
    1,
    'detector should flag the ad hoc format in a synthetic bad example',
  );
});

test('chrono format contract rejects direct to_rfc3339_opts helper bypasses', () => {
  const synthetic = `
pub fn bad() {
    let now = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
    use_now(now);
}
`;
  const findings = scanFileForForbiddenChronoFormat(synthetic, 'synthetic.rs');
  assert.equal(
    findings.length,
    1,
    'detector should flag direct to_rfc3339_opts in a synthetic bad example',
  );
});

test('chrono format contract accepts canonical domain helpers', () => {
  const synthetic = `
pub fn good() {
    let now = lorvex_domain::format_sync_timestamp(chrono::Utc::now());
    use_now(now);
}
pub fn also_good() {
    let now = lorvex_domain::sync_timestamp_now();
    use_now(now);
}
`;
  const findings = scanFileForForbiddenChronoFormat(synthetic, 'synthetic.rs');
  assert.equal(
    findings.length,
    0,
    'detector must NOT flag canonical domain timestamp helpers',
  );
});
