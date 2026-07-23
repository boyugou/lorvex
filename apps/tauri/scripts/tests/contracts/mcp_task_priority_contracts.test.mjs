import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('task priority write surfaces reuse one shared contract and runtime validator', () => {
  // server_contract/task.rs has been split into a task/ subtree. Read the
  // entire subtree so the priority constants and schemars annotations are
  // matched wherever the per-shape sibling owns them.
  const contractSource = readRustSources(
    'mcp-server/src/contract.rs',
    'mcp-server/src/contract/task',
    'lorvex-domain/src/validation/limits.rs',
  );
  // normalize_task_priority is owned by lorvex-workflow's task_create
  // subtree and reused from the task_update path; mcp-server reaches it
  // only via the workflow crate, so the priority validator source lives
  // there.
  const priorityValidatorSource = readRustSources(
    'lorvex-workflow/src/task_create',
    'lorvex-workflow/src/task_update',
  );
  const mutationsSource = readRustSources(
    'mcp-server/src/tasks/mutations/mod.rs',
    'mcp-server/src/tasks/mutations',
    'lorvex-workflow/src/task_create',
    'lorvex-workflow/src/task_batch_create.rs',
  );
  assert.match(
    contractSource,
    /pub(?:\(crate\))? const TASK_PRIORITY_ALLOWED_VALUES_DISPLAY: &str =[\s\S]+?;/,
    'shared task priority display constant must remain defined in one canonical place (lorvex-domain validation limits)',
  );
  assert.match(
    contractSource,
    /pub\(crate\) const TASK_PRIORITY_FIELD_DESCRIPTION: &str =[\s\S]+?;/,
    'server_contract.rs should expose one shared task priority field description constant',
  );
  assert.match(
    contractSource,
    /#\[schemars\(description = TASK_PRIORITY_FIELD_DESCRIPTION(?:,\s*range\(min = \d+,\s*max = \d+\))?\)\]\s*pub\(crate\) priority: Option<u8>,/s,
    'task priority write fields should reuse TASK_PRIORITY_FIELD_DESCRIPTION instead of hand-maintained strings',
  );

  assert.match(
    priorityValidatorSource,
    /Invalid priority '\{other\}'\. Expected one of: 1, 2, 3/,
    'normalize_task_priority must emit a single canonical "Invalid priority" runtime error covering the 1|2|3 allow list',
  );
  assert.match(
    priorityValidatorSource,
    /let priority = normalize_task_priority\(priority\)\?;/,
    'shared task insert preparation must validate priority before insert/urgency computation',
  );
  assert.match(
    priorityValidatorSource,
    /crate::task_create::normalize_task_priority\(Some\(\*value\)\)\?/,
    'task_update must route Patch::Set priority values through the shared normalize_task_priority validator',
  );
  assert.match(
    mutationsSource,
    /BatchCreateTaskInput[\s\S]*lorvex_workflow::task_batch_create::batch_create_tasks/,
    'batch_create_tasks should route inserts through the shared priority normalization path',
  );
});
