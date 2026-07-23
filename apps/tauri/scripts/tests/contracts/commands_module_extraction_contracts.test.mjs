import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('commands root delegates day-context helpers to a dedicated module', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );

  assert.match(
    source,
    /^pub\(crate\) mod day_context;$/m,
    'commands.rs should register a dedicated day_context leaf module',
  );
  assert.match(
    source,
    /^pub\(crate\) use day_context::\{[\s\S]*normalize_date_input_for_conn[\s\S]*trailing_day_window_bounds_for_conn[\s\S]*\};$/m,
    'commands.rs should re-export the canonical conn-aware day-context helpers from day_context.rs',
  );
  assert.doesNotMatch(
    source,
    /\nfn today_ymd_for_timezone_name\(|\nfn date_plus_days_ymd_for_timezone_name\(|\nfn trailing_day_window_bounds_for_conn\(|\nfn normalize_date_input_for_conn\(|\nfn compute_task_urgency_for_conn\(/,
    'commands.rs should not keep inline day-context helper implementations after extraction',
  );
});

test('CLI shared date offset helper delegates to workflow timezone helper', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'lorvex-cli/src/commands/shared/effects/mod.rs'),
    'utf8',
  );

  const helperBody = source.match(
    /pub\(crate\) fn date_plus_days_ymd_for_conn\([\s\S]*?\n\}/,
  )?.[0] ?? '';
  assert.match(
    helperBody,
    /lorvex_workflow::timezone::date_plus_days_ymd_for_conn\(\s*conn,\s*offset_days,\s*\)\?/,
    'CLI date offset helper should be a thin wrapper over lorvex_workflow::timezone::date_plus_days_ymd_for_conn',
  );
  assert.doesNotMatch(
    helperBody,
    /anchored_timezone_name_for_conn|date_plus_days_ymd_for_timezone_name|Utc::now/,
    'CLI date offset helper should not reimplement workflow timezone resolution or date math',
  );
});

test('commands root delegates list commands to a dedicated module', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );
  const listsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/lists/mod.rs'),
    'utf8',
  );

  assert.match(
    source,
    /^pub\(crate\) mod lists;$/m,
    'commands.rs should register a dedicated lists leaf module',
  );
  assert.match(
    listsSource,
    /^pub use queries::\{[\s\S]*get_list_with_tasks[\s\S]*\};$/m,
    'commands/lists/mod.rs should re-export list commands from the lists subtree',
  );
  assert.doesNotMatch(
    source,
    /\n#\[tauri::command\]\npub fn get_all_lists\(|\n#\[tauri::command\]\npub fn get_list_with_tasks\(|\n#\[tauri::command\]\npub fn delete_list\(|\nfn delete_list_internal\(|\nfn query_list_tasks_with_recent_completed\(/,
    'commands.rs should not keep inline list command/query implementations after extraction',
  );
});
