import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_focus_schedule is organized as a folder-backed subsystem with propose + save modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/focus/schedule/mod.rs'),
    'utf8',
  );
  const proposeSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/focus/schedule/propose.rs'),
    'utf8',
  );
  const saveSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/focus/schedule/save.rs'),
    'utf8',
  );
  const sharedSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/focus/schedule/shared/mod.rs'),
    'utf8',
  );
  const testsSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/focus/schedule/tests.rs'),
    'utf8',
  );

  for (const moduleName of ['propose', 'save']) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.match(rootSource, /^pub\(crate\) mod shared;$/m);
  assert.match(rootSource, /^#\[cfg\(test\)\]$/m);
  assert.match(rootSource, /^mod tests;$/m);
  // accept module was removed — save_focus_schedule now directly applies to current_focus
  assert.doesNotMatch(rootSource, /accept/);
  assert.match(rootSource, /^pub\(crate\) use propose::propose_daily_schedule;$/m);
  assert.match(rootSource, /^pub\(crate\) use save::save_focus_schedule;$/m);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn propose_daily_schedule\(|\npub\(crate\) fn save_focus_schedule\(|\nfn normalize_focus_schedule_row\(|\n#\[cfg\(test\)\]\nmod tests \{/,
    'server_focus_schedule root should remain a composition root after folder extraction',
  );

  assert.match(proposeSource, /\npub\(crate\) fn propose_daily_schedule\(/);
  assert.match(saveSource, /\npub\(crate\) fn save_focus_schedule\(/);
  assert.match(sharedSource, /\npub\(crate\) fn normalize_focus_schedule_row\(/);
  assert.match(testsSource, /\nfn save_focus_schedule_response_parses_blocks_array\(/);
  assert.match(testsSource, /\nfn save_focus_schedule_applies_task_blocks_to_current_focus\(/);
});
