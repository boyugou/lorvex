import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');

test('daily-review upsert requires an explicit expected_date across IPC boundaries', () => {
  const rustCommand = read('app/src-tauri/src/commands/reviews.rs');
  const rustTests = read('app/src-tauri/src/commands/tests/reviews.rs');
  const tsIpc = read('app/src/lib/ipc/tasks/reviews.ts');

  assert.doesNotMatch(
    rustCommand,
    /#\[serde\(default\)\]\s*pub expected_date:\s*Option<String>/,
    'Rust daily-review IPC input should not default or optionalize expected_date',
  );
  assert.doesNotMatch(
    rustCommand,
    /resolve_review_date\(expected_date:\s*Option<&str>/,
    'review-date resolver should not accept a missing expected_date path',
  );
  assert.doesNotMatch(
    rustCommand,
    /fall back to `today`|falls back to `today_ymd_for_conn`|legacy call path/i,
    'daily-review command docs should not document missing-date fallback behavior',
  );
  assert.doesNotMatch(
    rustTests,
    /falls_back_to_today|without expected_date|Legacy callers/i,
    'daily-review tests should not preserve missing expected_date fallback cases',
  );
  assert.doesNotMatch(
    tsIpc,
    /expected_date\?:\s*string/,
    'TypeScript IPC input should require expected_date',
  );
  assert.doesNotMatch(
    tsIpc,
    /If omitted|falls back to `today_ymd_for_conn`|pre-fix behavior/i,
    'TypeScript IPC docs should not describe missing-date fallback behavior',
  );
});
