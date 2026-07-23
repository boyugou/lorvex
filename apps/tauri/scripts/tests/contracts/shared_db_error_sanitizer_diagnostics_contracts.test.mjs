import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('shared DB error sanitizer persists unmatched diagnostics instead of stderr', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/shared/db_error_sanitize.rs'),
    'utf8',
  );
  const sanitizeBody = source.match(/pub\(crate\) fn sanitize_db_error\([\s\S]*?\n\}/);
  const unmatchedHelper = source.match(
    /fn append_unmatched_db_error_log_best_effort\([\s\S]*?\n\}/,
  );

  assert.ok(sanitizeBody, 'sanitize_db_error must remain an explicit shared boundary');
  assert.ok(unmatchedHelper, 'unmatched DB sanitizer diagnostics helper must remain explicit');
  assert.doesNotMatch(
    sanitizeBody[0],
    /eprintln!\s*\(/,
    'unmatched DB sanitizer diagnostics must not write stderr directly in packaged app builds',
  );
  assert.doesNotMatch(
    unmatchedHelper[0],
    /eprintln!\s*\(/,
    'unmatched DB sanitizer diagnostics helper must not write stderr directly',
  );
  assert.match(sanitizeBody[0], /append_unmatched_db_error_log_best_effort/);
  assert.match(unmatchedHelper[0], /try_append_error_log_best_effort/);
  assert.match(source, /shared\.sanitize_db_error\.unmatched/);
});
