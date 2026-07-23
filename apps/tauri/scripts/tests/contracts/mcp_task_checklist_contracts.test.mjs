import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('MCP task responses keep checklist_items as a first-class enrichment owned by lorvex_workflow', () => {
  // query_support owns enrichment delegation in mcp-server. Read all non-test
  // siblings so the contract finds the call wherever it lands.
  const querySupportDir = path.join(repoRoot, 'mcp-server/src/system/handler_support/query_support');
  const querySupport = fs
    .readdirSync(querySupportDir)
    .filter((name) => name.endsWith('.rs') && name !== 'tests.rs')
    .map((name) => fs.readFileSync(path.join(querySupportDir, name), 'utf8'))
    .join('\n');
  // Post-#3330: shared_ops moved out of lorvex-store into lorvex-workflow.
  const taskEnrichment = fs.readFileSync(
    path.join(repoRoot, 'lorvex-workflow/src/task_enrichment/mod.rs'),
    'utf8',
  );

  assert.match(
    taskEnrichment,
    /pub struct ChecklistItemData/,
    'task enrichment should expose a ChecklistItemData struct used to attach checklist arrays',
  );
  assert.match(
    taskEnrichment,
    /pub struct Enrichment[\s\S]*checklist_items:\s*Option<Vec<ChecklistItemData>>/,
    'Enrichment should carry checklist_items as a first-class field',
  );
  assert.match(
    taskEnrichment,
    /pub fn compute_enrichments\(/,
    'task enrichment should expose compute_enrichments as the canonical batch entry point',
  );

  assert.match(
    querySupport,
    /task_enrichment::compute_enrichments\(/,
    'MCP query support should delegate shared enrichments (including checklists) to lorvex_workflow::task_enrichment',
  );
});

test('MCP task router exposes explicit checklist mutation tools with dedicated lifecycle contracts', () => {
  // Post-#3370 flat-tree: router lives at tasks/router.rs.
  const router = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/router.rs'),
    'utf8',
  );
  const lifecycleContracts = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/contract/task/lifecycle.rs'),
    'utf8',
  );

  for (const toolName of [
    'add_task_checklist_item',
    'update_task_checklist_item',
    'toggle_task_checklist_item',
    'remove_task_checklist_item',
    'reorder_task_checklist_items',
  ]) {
    // The router uses the `write <tool_name>(<ArgsType>) -> lifecycle::<tool_name>;`
    // DSL macro to register tools — assert the per-tool row is present.
    assert.match(
      router,
      new RegExp(`write\\s+${toolName}\\([\\s\\S]*?->\\s*lifecycle::${toolName};`),
      `task router should register ${toolName} via the lifecycle delegation DSL`,
    );
  }

  for (const contractName of [
    'AddTaskChecklistItemArgs',
    'UpdateTaskChecklistItemArgs',
    'ToggleTaskChecklistItemArgs',
    'RemoveTaskChecklistItemArgs',
    'ReorderTaskChecklistItemsArgs',
  ]) {
    assert.match(
      lifecycleContracts,
      new RegExp(`\\bstruct ${contractName}\\b`),
      `task lifecycle contracts should define ${contractName}`,
    );
  }
});

test('MCP checklist completion mutation requires explicit set semantics', () => {
  const router = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/router.rs'),
    'utf8',
  );
  const lifecycleContracts = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/contract/task/lifecycle.rs'),
    'utf8',
  );
  const checklistWritePath = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/lifecycle/writes/checklist.rs'),
    'utf8',
  );
  const docs = fs.readFileSync(
    path.join(repoRoot, 'docs/design/MCP_TOOLS.md'),
    'utf8',
  );

  assert.match(
    lifecycleContracts,
    /struct ToggleTaskChecklistItemArgs \{[\s\S]*pub\(crate\) completed: bool,/,
    'toggle_task_checklist_item should require an explicit completed target',
  );
  assert.doesNotMatch(
    lifecycleContracts,
    /ToggleTaskChecklistItemArgs[\s\S]*completed: Option<bool>/,
    'toggle_task_checklist_item should not accept omitted completed values',
  );
  assert.doesNotMatch(
    checklistWritePath,
    /unwrap_or\(!was_completed\)/,
    'checklist completion writes should not invert current state on omitted completed',
  );
  for (const source of [router, docs]) {
    assert.doesNotMatch(
      source,
      /omit completed|Omit to invert|invert the current/i,
      'tool descriptions should not advertise retry-unsafe invert semantics',
    );
  }
});
