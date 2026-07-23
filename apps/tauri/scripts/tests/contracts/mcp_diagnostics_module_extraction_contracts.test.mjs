import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('mcp diagnostics helpers live in a dedicated module instead of server_handler_support', () => {
  const diagnosticsPath = path.join(repoRoot, 'mcp-server/src/system/diagnostics/mod.rs');
  const helpersSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/system/handler_support.rs'), 'utf8');
  const logsSource = readRustSources(
    'mcp-server/src/system/logs/mod.rs',
    'mcp-server/src/system/logs',
  );
  const overviewSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/overview.rs'),
    'utf8',
  );
  const listHealthSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/lists/health/mod.rs'),
    'utf8',
  );
  const weeklyReviewSource = readRustSources(
    'mcp-server/src/reviews/weekly/mod.rs',
    'mcp-server/src/reviews/weekly/snapshot.rs',
  );

  assert.ok(
    fs.existsSync(diagnosticsPath),
    'server_diagnostics.rs should exist as the dedicated home for diagnostics/log text helpers',
  );

  const diagnosticsSource = fs.readFileSync(diagnosticsPath, 'utf8');

  for (const snippet of [
    'fn normalize_log_level(',
    'fn log_level_to_str(',
    'fn level_for_changelog_operation(',
    'fn truncate_diagnostic_text(',
    'fn truncate_compact_text(',
    'fn clamp_rows_text_field(',
    'fn redact_diagnostic_text(',
    'fn sanitize_diagnostic_text(',
    'fn increment_source_count(',
  ]) {
    assert.doesNotMatch(
      helpersSource,
      new RegExp(snippet.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      `server_handler_support.rs should not keep inline diagnostics helper ${snippet}`,
    );
  }

  assert.match(
    diagnosticsSource,
    /pub\(crate\)\s+fn normalize_log_level\([\s\S]*pub\(crate\)\s+fn increment_source_count\(/,
    'server_diagnostics.rs should own log-level normalization, truncation/redaction, and source count helpers',
  );
  assert.match(
    logsSource,
    /use crate::system::diagnostics::\{[\s\S]*normalize_log_level[\s\S]*sanitize_diagnostic_text[\s\S]*}/,
    'server_logs.rs should import diagnostics helpers from the dedicated module',
  );
  assert.match(
    overviewSource,
    /use crate::system::diagnostics::\{[^}]*clamp_rows_text_field[^}]*truncate_compact_text[^}]*\};/,
    'server_overview.rs should import row clamping and compact truncation from the dedicated diagnostics module',
  );
  assert.match(
    listHealthSource,
    /use crate::system::diagnostics::clamp_rows_text_field;/,
    'server_list_health.rs should import row clamping from the dedicated diagnostics module',
  );
  assert.match(
    weeklyReviewSource,
    /use crate::system::diagnostics::clamp_rows_text_field;/,
    'server_weekly_review snapshot should import row clamping from the dedicated diagnostics module',
  );
});
