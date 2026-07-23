import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('MCP task batch is organized as a folder-backed subsystem with focused batch operation modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/tasks/batch/mod.rs'), 'utf8');
  const cancelSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/batch/cancel/mod.rs'),
    'utf8',
  );
  const completeSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/batch/complete.rs'),
    'utf8',
  );
  const moveSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/batch/move_tasks.rs'),
    'utf8',
  );
  const updateRootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/batch/update/mod.rs'),
    'utf8',
  );
  const updateSource = readRustSources(
    'mcp-server/src/tasks/batch/update/mod.rs',
    'mcp-server/src/tasks/batch/update/effects.rs',
  );

  for (const moduleName of ['cancel', 'complete', 'move_tasks', 'update']) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.match(rootSource, /^pub\(crate\) use cancel::batch_cancel_tasks_in_list;$/m);
  assert.match(rootSource, /^pub\(crate\) use complete::batch_complete_tasks;$/m);
  assert.match(rootSource, /^pub\(crate\) use move_tasks::batch_move_tasks;$/m);
  assert.match(rootSource, /^pub\(crate\) use update::batch_update_tasks;$/m);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn batch_cancel_tasks_in_list\(|\npub\(crate\) fn batch_complete_tasks\(|\npub\(crate\) fn batch_move_tasks\(|\npub\(crate\) fn batch_update_tasks\(/,
    'MCP task batch root should remain a composition root after folder extraction',
  );
  assert.match(cancelSource, /\npub\(crate\) fn batch_cancel_tasks_in_list\(/);
  assert.match(completeSource, /\npub\(crate\) fn batch_complete_tasks\(/);
  assert.match(moveSource, /\npub\(crate\) fn batch_move_tasks\(/);
  assert.match(updateRootSource, /^mod effects;$/m);
  assert.match(updateSource, /\npub\(crate\) fn batch_update_tasks\(/);
  assert.match(
    updateSource,
    /\nfn workflow_batch_update_patch\([\s\S]*\npub\(super\) fn flush_batch_update_effects\(/,
  );
});
