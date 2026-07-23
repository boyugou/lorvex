import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('task due_date schema descriptions and runtime errors reuse one shared accepted-format summary', () => {
  const contractSource = readRustSources(
    'mcp-server/src/contract.rs',
    // server_contract/task.rs has been split into task/ with per-shape siblings
    // (single_create, single_update, batch_create, batch_update, lists, queries, ...).
    // Read the entire task/ subtree so the contract matches wherever the
    // due_date schema constants/usages landed.
    'mcp-server/src/contract/task',
  );
  const taskSupportSource = readRustSources(
    'mcp-server/src/tasks/support.rs',
    'mcp-server/src/tasks/support/normalization.rs',
    'mcp-server/src/tasks/support/status.rs',
  );

  assert.match(
    contractSource,
    /pub\(crate\) const DUE_DATE_ALLOWED_INPUT_SUMMARY: &str =[\s\S]+?;/,
    'server_contract.rs should expose one canonical due_date accepted-format summary',
  );
  assert.match(
    contractSource,
    /pub\(crate\) const DUE_DATE_FIELD_DESCRIPTION: &str = concat!\(/,
    'Create-style due_date field descriptions should derive from one shared Rust constant',
  );
  assert.match(
    contractSource,
    /pub\(crate\) const DUE_DATE_PATCH_FIELD_DESCRIPTION: &str = concat!\(/,
    'Patch-style due_date field descriptions should derive from one shared Rust constant',
  );

  const createStyleMatches = Array.from(
    contractSource.matchAll(
      /#\[schemars\(description = DUE_DATE_FIELD_DESCRIPTION\)\]\s*pub\(crate\) due_date: Option<String>,/gs,
    ),
  );
  assert.equal(
    createStyleMatches.length,
    2,
    'CreateTaskArgs.due_date and BatchCreateTaskInput.due_date should reuse DUE_DATE_FIELD_DESCRIPTION',
  );

  const patchStyleMatches = Array.from(
    contractSource.matchAll(
      /#\[schemars\(description = DUE_DATE_PATCH_FIELD_DESCRIPTION\)\]\s*#\[serde\(default, skip_serializing_if = "Patch::is_unset"\)\]\s*pub\(crate\) due_date: Patch<String>,/gs,
    ),
  );
  assert.equal(
    patchStyleMatches.length,
    2,
    'UpdateTaskArgs.due_date and BatchUpdateTaskPatch.due_date should reuse DUE_DATE_PATCH_FIELD_DESCRIPTION with Patch<String> tri-state semantics',
  );

  assert.match(
    taskSupportSource,
    /Expected \{DUE_DATE_ALLOWED_INPUT_SUMMARY\}/,
    'normalize_due_date_input should reuse DUE_DATE_ALLOWED_INPUT_SUMMARY instead of retyping accepted formats',
  );
});
