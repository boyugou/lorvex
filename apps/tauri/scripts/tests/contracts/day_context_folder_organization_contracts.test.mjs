import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('day_context is organized as a folder-backed subsystem with focused helper modules', () => {
  const entrySource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/day_context.rs'),
    'utf8',
  );
  const parsingSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/day_context/parsing.rs'),
    'utf8',
  );
  const windowSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/day_context/window.rs'),
    'utf8',
  );
  // Shared timezone/today helpers were lifted into the lorvex-store crate so
  // the MCP server and Tauri app can share one source of truth.
  const sharedTimezoneSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-workflow/src/timezone/mod.rs'),
    'utf8',
  );
  assert.match(entrySource, /^mod parsing;$/m);
  assert.match(entrySource, /^mod window;$/m);
  assert.match(entrySource, /^pub\(crate\) use parsing::normalize_date_input_for_conn;$/m);
  assert.match(entrySource, /^pub\(crate\) use window::trailing_day_window_bounds_for_conn;$/m);
  assert.match(entrySource, /^#\[cfg\(test\)\]$/m);
  assert.match(entrySource, /normalize_date_input_for_timezone/);
  assert.match(entrySource, /trailing_day_window_bounds_for_conn_at/);
  assert.doesNotMatch(
    entrySource,
    /\npub\(crate\) fn today_ymd_for_conn\(|\npub\(crate\) fn trailing_day_window_bounds_for_conn\(/,
    'day_context.rs should stay a composition root after folder extraction',
  );

  assert.match(parsingSource, /\npub\(crate\) fn normalize_date_input_for_conn\(/);
  assert.match(parsingSource, /(?:^|\n)pub\(crate\) fn normalize_date_input_for_timezone/);
  assert.match(sharedTimezoneSource, /\npub fn active_timezone_name\(/);
  assert.match(sharedTimezoneSource, /\npub fn today_ymd_for_conn\(/);
  assert.match(windowSource, /\npub\(crate\) fn trailing_day_window_bounds_for_conn\(/);
});
