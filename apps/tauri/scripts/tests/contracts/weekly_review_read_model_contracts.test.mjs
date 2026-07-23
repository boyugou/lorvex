import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('weekly review reads share the workflow read model across app CLI and MCP', () => {
  const workflowLib = read('lorvex-workflow/src/lib.rs');
  const workflowWeeklyReview = [
    read('lorvex-workflow/src/weekly_review/mod.rs'),
    read('lorvex-workflow/src/weekly_review/read_model.rs'),
    read('lorvex-workflow/src/weekly_review/brief.rs'),
    read('lorvex-workflow/src/weekly_review/snapshot.rs'),
  ].join('\n');
  const tauriReviews = read('app/src-tauri/src/commands/reviews.rs');
  const cliWeekly = read('lorvex-cli/src/commands/mutate/reviews/effects/weekly.rs');
  const mcpWeeklyReads = [
    read('mcp-server/src/reviews/weekly/brief.rs'),
    read('mcp-server/src/reviews/weekly/snapshot.rs'),
  ].join('\n');

  assert.match(workflowLib, /pub mod weekly_review;/);
  assert.match(
    workflowWeeklyReview,
    /pub fn load_weekly_review\(/,
    'workflow should expose the app weekly review read model',
  );
  assert.match(
    workflowWeeklyReview,
    /pub fn load_weekly_review_brief\(/,
    'workflow should expose the assistant weekly review brief read model',
  );
  assert.match(
    workflowWeeklyReview,
    /pub fn load_weekly_review_snapshot\(/,
    'workflow should expose the assistant weekly review snapshot read model',
  );

  for (const [name, source] of [
    ['Tauri weekly review command', tauriReviews],
    ['CLI weekly review effects', cliWeekly],
    ['MCP weekly review reads', mcpWeeklyReads],
  ]) {
    assert.match(
      source,
      /lorvex_workflow::weekly_review/,
      `${name} should adapt the shared weekly review read model`,
    );
  }

  assert.doesNotMatch(
    tauriReviews,
    /SELECT\s+\{TASK_COLS\}[\s\S]+FROM tasks[\s\S]+weekly review/i,
    'Tauri weekly review should not own task-section SQL',
  );
  assert.doesNotMatch(
    cliWeekly,
    /const\s+\w+_SQL|fn\s+load_weekly_review_task_items|fn\s+load_stalled_lists/,
    'CLI weekly review should not own section SQL or row mappers',
  );
  assert.doesNotMatch(
    mcpWeeklyReads,
    /SELECT\s+\*\s+FROM\s+tasks|query_all_as_json|enrich_and_fence_tasks_for_response/,
    'MCP weekly review should serialize explicit weekly review DTOs instead of full task rows',
  );
});
