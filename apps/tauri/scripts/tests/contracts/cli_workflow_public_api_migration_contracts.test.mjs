import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('CLI checklist workflow writes call the shared workflow owner, not MCP public_api shims', () => {
  const source = read('lorvex-cli/src/commands/workflow/checklist.rs');

  assert.match(
    source,
    /lorvex_workflow::task_checklist/,
    'checklist CLI writes should route through lorvex-workflow task_checklist operations',
  );
  assert.doesNotMatch(
    source,
    /lorvex_mcp_server::public_api|public_api::/,
    'checklist CLI writes must not call MCP JSON public_api shims after their workflow migration',
  );
  assert.doesNotMatch(
    source,
    /\bmap_public_api_error\b/,
    'checklist CLI writes should map typed workflow/store errors directly instead of MCP string errors',
  );
});

test('CLI recurrence workflow writes call the shared workflow owner, not MCP public_api shims', () => {
  const source = read('lorvex-cli/src/commands/workflow/recurrence.rs');

  assert.match(
    source,
    /lorvex_workflow::task_recurrence/,
    'recurrence CLI writes should route through lorvex-workflow task_recurrence operations',
  );
  assert.doesNotMatch(
    source,
    /lorvex_mcp_server::public_api|public_api::/,
    'recurrence CLI writes must not call MCP JSON public_api shims after their workflow migration',
  );
  assert.doesNotMatch(
    source,
    /\bmap_public_api_error\b/,
    'recurrence CLI writes should map typed workflow/store errors directly instead of MCP string errors',
  );
});

test('CLI list reorganize workflow writes call the shared workflow owner, not MCP public_api shims', () => {
  const source = read('lorvex-cli/src/commands/workflow/list_ops.rs');

  assert.match(
    source,
    /lorvex_workflow::list_reorganize/,
    'list reorganize CLI writes should route through lorvex-workflow list_reorganize operations',
  );
  assert.doesNotMatch(
    source,
    /public_api::reorganize_list/,
    'list reorganize CLI writes must not call MCP JSON public_api shims after their workflow migration',
  );
});

test('CLI permanent-delete workflow writes call the shared workflow owner, not MCP public_api shims', () => {
  const source = read('lorvex-cli/src/commands/workflow/list_ops.rs');

  assert.match(
    source,
    /lorvex_workflow::task_permanent_delete/,
    'permanent-delete CLI writes should call the typed shared workflow owner',
  );
  assert.doesNotMatch(
    source,
    /public_api::permanent_delete_task/,
    'permanent-delete CLI writes must not call MCP JSON public_api shims after their workflow migration',
  );
});

test('CLI batch-cancel-in-list workflow writes call the shared workflow owner, not MCP public_api shims', () => {
  const source = [
    read('lorvex-cli/src/commands/workflow/tasks/batch_cancel/mod.rs'),
    read('lorvex-cli/src/commands/workflow/tasks/batch_cancel/flush.rs'),
  ].join('\n');

  assert.match(
    source,
    /lorvex_workflow::task_batch_cancel/,
    'batch-cancel-in-list CLI writes should call the typed shared workflow owner',
  );
  assert.doesNotMatch(
    source,
    /public_api_for_batch_cancel_in_list/,
    'batch-cancel-in-list CLI writes must not call MCP JSON public_api shims after their workflow migration',
  );
});

test('CLI batch-create workflow writes call the shared workflow owner, not MCP public_api shims', () => {
  const source = read('lorvex-cli/src/commands/workflow/tasks/batch_create.rs');

  assert.match(
    source,
    /lorvex_workflow::task_batch_create/,
    'batch-create CLI writes should call the typed shared workflow owner',
  );
  assert.doesNotMatch(
    source,
    /public_api_for_batch_create/,
    'batch-create CLI writes must not call MCP JSON public_api shims after their workflow migration',
  );
});

test('CLI task-create workflow writes call the shared workflow owner, not MCP public_api shims', () => {
  const source = read('lorvex-cli/src/commands/workflow/tasks/create.rs');

  assert.match(
    source,
    /lorvex_workflow::task_create/,
    'task-create CLI writes should call the typed shared workflow owner',
  );
  assert.doesNotMatch(
    source,
    /public_api_for_create_task/,
    'task-create CLI writes must not call MCP JSON public_api shims after their workflow migration',
  );
});

test('CLI batch-update workflow writes call the shared workflow owner, not MCP public_api shims', () => {
  const source = read('lorvex-cli/src/commands/workflow/tasks/batch_update.rs');

  assert.match(
    source,
    /lorvex_workflow::task_batch_update/,
    'batch-update CLI writes should call the typed shared workflow owner',
  );
  assert.doesNotMatch(
    source,
    /public_api_for_batch_update/,
    'batch-update CLI writes must not call MCP JSON public_api shims after their workflow migration',
  );
});

test('migrated workflow write public_api shims stay deleted from mcp-server', () => {
  const source = read('mcp-server/src/public_api.rs');

  for (const removedShim of [
    'set_recurrence',
    'add_task_checklist_item',
    'update_task_checklist_item',
    'toggle_task_checklist_item',
    'remove_task_checklist_item',
    'reorder_task_checklist_items',
    'reorganize_list',
    'permanent_delete_task',
    'public_api_for_create_task',
    'public_api_for_batch_create',
    'public_api_for_batch_update',
    'public_api_for_batch_cancel_in_list',
  ]) {
    assert.doesNotMatch(
      source,
      new RegExp(`pub fn ${removedShim}\\b`),
      `${removedShim} should stay out of mcp-server public_api after the CLI workflow write migration`,
    );
  }
});
