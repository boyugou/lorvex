import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('server_task_mutations is organized as a folder-backed subsystem with create update batch and shared support modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/mutations/mod.rs'),
    'utf8',
  );
  const createSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/mutations/create/mod.rs'),
    'utf8',
  );
  const updateRootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/mutations/update/mod.rs'),
    'utf8',
  );
  const updateSource = readRustSources(
    'mcp-server/src/tasks/mutations/update/mod.rs',
  );
  // PreparedTaskUpdate, build_update_statement, apply_*_side_effects, and
  // build_update_summary live in the lorvex-workflow task_update/effects
  // subtree — every mcp-server caller routes through that crate.
  const workflowTaskUpdateEffectsSource = readRustSources(
    'lorvex-workflow/src/task_update/effects',
  );
  const batchSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/mutations/batch/mod.rs'),
    'utf8',
  );
  const workflowTaskCreatePreparedSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-workflow/src/task_create/prepared.rs'),
    'utf8',
  );
  const workflowTaskCreateInputSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-workflow/src/task_create/input.rs'),
    'utf8',
  );

  for (const moduleName of ['batch', 'create', 'update']) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.match(rootSource, /^pub\(crate\) use batch::batch_create_tasks;$/m);
  assert.match(rootSource, /^pub\(crate\) use create::create_task;$/m);
  assert.match(rootSource, /^pub\(crate\) use update::update_task;$/m);
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn create_task\(|\npub\(crate\) fn update_task\(|\npub\(crate\) fn batch_create_tasks\(/,
    'server_task_mutations root should remain a composition root after folder extraction',
  );
  assert.match(createSource, /\npub\(crate\) fn create_task\(/);
  assert.match(updateSource, /\npub\(crate\) fn update_task\(/);
  // update mod.rs is a thin MCP adapter; the prepare/apply layers live
  // in lorvex-workflow's task_update/effects subtree.
  assert.match(
    workflowTaskUpdateEffectsSource,
    /\npub\(in crate::task_update\) struct PreparedTaskUpdate \{/,
  );
  assert.match(
    workflowTaskUpdateEffectsSource,
    /\bapply_dependency_patch\b[\s\S]*\bprepare_task_update\b[\s\S]*\bapply_primary_row_patch\b[\s\S]*\bapply_status_transition\b/,
  );
  assert.match(batchSource, /\npub\(crate\) fn batch_create_tasks\(/);
  assert.match(workflowTaskCreatePreparedSource, /\npub fn prepare_task_insert\(/);
  assert.match(workflowTaskCreateInputSource, /\npub struct CreateTaskInput \{/);
});
