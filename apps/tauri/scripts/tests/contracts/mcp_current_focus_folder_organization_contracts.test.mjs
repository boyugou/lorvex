import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

test('server_current_focus is organized as a folder-backed subsystem with focused model, reads, writes, and tests modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/focus/current.rs'),
    'utf8',
  );
  const modelSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/focus/current/model/mod.rs'),
    'utf8',
  );
  const readsSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/focus/current/reads.rs'),
    'utf8',
  );
  const writesSource = [
    'mod.rs', 'add.rs', 'audit.rs', 'clear.rs', 'remove.rs', 'set.rs',
  ]
    .map((name) => fs.readFileSync(
      path.join(repoRoot, `mcp-server/src/focus/current/writes/${name}`),
      'utf8',
    ))
    .join('\n');
  const testsSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/focus/current/tests.rs'),
    'utf8',
  );

  for (const moduleName of ['model', 'reads', 'writes']) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.match(rootSource, /^#\[cfg\(test\)\]$/m);
  assert.match(rootSource, /^mod tests;$/m);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'model',
    symbols: 'enrich_current_focus_row',
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'reads',
    symbols: 'get_current_focus',
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'writes',
    symbols: ['add_to_current_focus', 'clear_current_focus', 'remove_from_current_focus', 'set_current_focus'],
  }), true);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn set_current_focus\(|\npub\(crate\) fn get_current_focus\(|\npub\(crate\) fn clear_current_focus\(|\n#\[cfg\(test\)\]\nmod tests \{/,
    'server_current_focus root should stay a composition root after folder extraction',
  );

  // CURRENT_FOCUS_TASK_IDS_MAX moved to lorvex-workflow as the canonical
  // home (#3066 lift) — the model module imports it from there.
  const workflowCurrentFocusSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-workflow/src/current_focus.rs'),
    'utf8',
  );
  assert.match(
    workflowCurrentFocusSource,
    /\npub const CURRENT_FOCUS_TASK_IDS_MAX: usize = 50;/,
    'CURRENT_FOCUS_TASK_IDS_MAX should live canonically in lorvex-workflow::current_focus',
  );
  assert.match(modelSource, /\npub\(crate\) fn enrich_current_focus_row\(/);
  assert.match(readsSource, /\npub\(crate\) fn get_current_focus\(/);
  assert.match(writesSource, /\npub\(crate\) fn set_current_focus\(/);
  assert.match(writesSource, /\npub\(crate\) fn clear_current_focus\(/);
  assert.match(testsSource, /\nfn set_current_focus_response_parses_task_ids_array\(/);
  assert.match(testsSource, /\nfn get_current_focus_response_parses_task_ids_array\(/);
});
