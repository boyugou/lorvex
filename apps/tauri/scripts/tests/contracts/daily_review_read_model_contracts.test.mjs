import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('daily review reads share the store read model across app CLI and MCP', () => {
  const storeDailyReview = read('lorvex-store/src/repositories/daily_review_ops/mod.rs');
  const tauriConstants = read('app/src-tauri/src/commands/shared/constants.rs');
  const tauriReviews = read('app/src-tauri/src/commands/reviews.rs');
  const cliDailyView = read('lorvex-cli/src/commands/mutate/reviews/effects/daily_view.rs');
  const mcpDailyReads = [
    read('mcp-server/src/reviews/daily/reads.rs'),
    read('mcp-server/src/reviews/daily/writes/add.rs'),
    read('mcp-server/src/reviews/daily/writes/amend.rs'),
  ].join('\n');

  assert.match(storeDailyReview, /pub const DAILY_REVIEW_ROW_COLS:/);
  assert.match(storeDailyReview, /pub struct DailyReviewRow/);
  assert.match(storeDailyReview, /pub fn get_daily_review_row\(/);
  assert.match(storeDailyReview, /pub fn list_daily_review_rows\(/);
  assert.match(storeDailyReview, /fn daily_review_row_from_sql_row\(/);

  assert.doesNotMatch(
    tauriConstants,
    /DAILY_REVIEW_COLS/,
    'Tauri must not own the daily review projection constants',
  );

  for (const [name, source] of [
    ['Tauri daily review reads', tauriReviews],
    ['CLI daily review reads', cliDailyView],
    ['MCP daily review reads/writes', mcpDailyReads],
  ]) {
    assert.match(
      source,
      /lorvex_store::daily_review_ops::DailyReviewRow|lorvex_store::daily_review_ops::get_daily_review_row|lorvex_store::daily_review_ops::list_daily_review_rows/,
      `${name} should adapt the store-owned DailyReviewRow`,
    );
  }

  assert.doesNotMatch(
    mcpDailyReads,
    /SELECT\s+\*\s+FROM\s+daily_reviews/i,
    'MCP daily review paths must not use SELECT *',
  );
  assert.doesNotMatch(
    cliDailyView,
    /SELECT\s+date,\s*summary,\s*mood,\s*energy_level[\s\S]+FROM daily_reviews/i,
    'CLI daily review reads should not hand-roll the header projection',
  );
  assert.doesNotMatch(
    tauriReviews,
    /daily_review_from_row|SELECT\s+\{DAILY_REVIEW_COLS\}/,
    'Tauri daily review reads should project the store row instead of owning a mapper',
  );
});
