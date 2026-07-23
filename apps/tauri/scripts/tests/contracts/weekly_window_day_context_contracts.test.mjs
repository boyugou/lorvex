import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('weekly review and overview surfaces derive trailing windows from conn-aware UTC boundary helpers', () => {
  const appOverviewSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/overview.rs'),
    'utf8',
  );
  const appReviewsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/reviews.rs'),
    'utf8',
  );
  const mcpOverviewSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/overview.rs'),
    'utf8',
  );
  const mcpWeeklyReviewSource = readRustSources(
    'mcp-server/src/reviews/weekly/mod.rs',
    'mcp-server/src/reviews/weekly/brief.rs',
    'mcp-server/src/reviews/weekly/snapshot.rs',
  );
  const workflowWeeklyReviewSource = readRustSources('lorvex-workflow/src/weekly_review');

  for (const [label, source] of [
    ['app overview', `${appOverviewSource}\n${workflowOverviewSource()}`],
    ['app reviews', `${appReviewsSource}\n${workflowWeeklyReviewSource}`],
    ['mcp overview', `${mcpOverviewSource}\n${workflowOverviewSource()}`],
    ['mcp weekly review', `${mcpWeeklyReviewSource}\n${workflowWeeklyReviewSource}`],
  ]) {
    assert.match(
      source,
      /trailing_day_window(?:_utc)?_bounds_for_conn\(/,
      `${label} should derive weekly windows from the conn-aware UTC boundary helper`,
    );
    assert.doesNotMatch(
      source,
      /datetime\('now', '-7 days'\)/,
      `${label} should not use rolling UTC datetime('now', '-7 days') windows`,
    );
  }
});

function workflowOverviewSource() {
  return readRustSources('lorvex-workflow/src/overview');
}

test('learning insights derive rolling windows from explicit UTC boundaries instead of SQLite datetime(now, ?)', () => {
  const source = readRustSources(
    'mcp-server/src/system/guidance/mod.rs',
    'mcp-server/src/system/guidance/task_pattern_analysis/mod.rs',
    'mcp-server/src/system/guidance/task_pattern_analysis',
  );

  assert.match(
    source,
    /trailing_day_window_bounds_for_conn\(conn,\s*i64::from\(window_days\)\)\?/,
    'server_guidance should derive the requested rolling window from the conn-aware UTC boundary helper',
  );
  assert.doesNotMatch(
    source,
    /datetime\('now', \?\)|datetime\('now', '-7 days'\)/,
    'server_guidance should not use SQLite rolling UTC datetime(now, ?) helpers for day-scoped windows',
  );
});
