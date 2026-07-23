import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_handler_support is organized as a folder-backed subsystem with focused clock, query, parsing, date, and vocabulary modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/handler_support.rs'),
    'utf8',
  );
  const clockSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/handler_support/clock.rs'),
    'utf8',
  );
  const dateSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/handler_support/date.rs'),
    'utf8',
  );
  const errorsSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/handler_support/errors/mod.rs'),
    'utf8',
  );
  const logFiltersSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/handler_support/log_filters.rs'),
    'utf8',
  );
  // query_support/mod.rs has been split into mod, task_id, suggestions, enrich (+ tests).
  // Read every non-test sibling so the contract finds helpers wherever the
  // refactor placed them.
  const querySupportDir = path.join(repoRoot, 'mcp-server/src/system/handler_support/query_support');
  const querySupportSource = fs
    .readdirSync(querySupportDir)
    .filter((fileName) => fileName.endsWith('.rs') && fileName !== 'tests.rs')
    .map((fileName) => fs.readFileSync(path.join(querySupportDir, fileName), 'utf8'))
    .join('\n');
  const testsSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/handler_support/tests.rs'),
    'utf8',
  );

  for (const moduleName of ['clock', 'date', 'device_state', 'errors', 'log_filters', 'query_support', 'router_glue']) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.match(rootSource, /^#\[cfg\(test\)\]$/m);
  assert.match(rootSource, /^mod tests;$/m);
  assert.match(rootSource, /^pub\(crate\) use clock::\{new_uuid, utc_now_iso\};$/m);
  assert.match(rootSource, /pub\(crate\) use date::\{[^}]*};/m);
  assert.match(rootSource, /\bresolve_optional_date\b/);
  assert.match(rootSource, /\bresolve_list_name\b/);
  assert.match(rootSource, /^pub\(crate\) use errors::\{load_failed_error, not_found_error, to_error_detail, to_error_message\};$/m);
  assert.match(
    rootSource,
    /pub\(crate\) use log_filters::\{[\s\S]*merge_requested_levels,[\s\S]*merge_requested_sources[\s\S]*};/m,
  );
  // The previous `parsing` submodule was retired — `parse_hhmm_to_minutes`
  // migrated into `lorvex-domain`, so server_handler_support no longer hosts a
  // dedicated parsing module.
  assert.doesNotMatch(
    rootSource,
    /^mod parsing;$/m,
    'server_handler_support should not declare a parsing submodule after parse_hhmm_to_minutes moved to lorvex-domain',
  );
  assert.match(rootSource, /^pub\(crate\) use query_support::\{[\s\S]*\};$/m);
  assert.match(rootSource, /\bbounded_limit_or_default\b/);
  assert.match(rootSource, /\bplural_s\b/);
  assert.match(rootSource, /\brequired_json_i64_field\b/);
  assert.match(rootSource, /\brequired_json_string_field\b/);
  assert.match(rootSource, /^pub\(crate\) use router_glue::\{[\s\S]*\};$/m);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) (?:const )?fn utc_now_iso\(|\npub\(crate\) (?:const )?fn optional_text_sql\(|\npub\(crate\) (?:const )?fn to_error_message\(/,
    'server_handler_support root should stay a composition root after folder extraction',
  );

  assert.match(clockSource, /pub\(crate\) (?:const )?fn utc_now_iso\(/);
  assert.match(clockSource, /pub\(crate\) (?:const )?fn new_uuid\(/);
  assert.match(dateSource, /pub\(crate\) (?:const )?fn resolve_optional_date\(/);
  assert.match(dateSource, /pub\(crate\) (?:const )?fn resolve_list_name\(/);
  assert.match(dateSource, /pub\(crate\) (?:const )?fn resolve_reminder_local_anchor\(/);
  assert.match(errorsSource, /pub\(crate\) (?:const )?fn to_error_detail\(/);
  assert.match(errorsSource, /pub\(crate\) (?:const )?fn to_error_message\(/);
  assert.match(querySupportSource, /pub\(crate\) (?:const )?fn bounded_limit_or_default\(/);
  assert.match(querySupportSource, /pub\(crate\) (?:const )?fn plural_s\(/);
  assert.match(querySupportSource, /pub\(crate\) (?:const )?fn required_json_i64_field\(/);
  assert.match(querySupportSource, /pub\(crate\) (?:const )?fn required_json_string_field(?:<[^>]+>)?\(/);
  assert.match(logFiltersSource, /pub\(crate\) (?:const )?fn merge_requested_levels\(/);
  assert.match(logFiltersSource, /pub\(crate\) (?:const )?fn merge_requested_sources\(/);
  assert.doesNotMatch(logFiltersSource, /pub\(crate\) (?:const )?fn optional_string_json\(/);
  assert.match(querySupportSource, /pub\(crate\) (?:const )?fn bounded_limit\(/);
  // After the query_support split, escape_like moved to task_id.rs and gained
  // a `pub(super)` visibility so siblings (e.g. suggestions.rs) can reach it.
  assert.match(querySupportSource, /\n(?:pub\(super\)\s+)?fn escape_like\(/);
  assert.match(testsSource, /fn utc_now_iso_uses_canonical_millisecond_sync_timestamp\(/);
});
