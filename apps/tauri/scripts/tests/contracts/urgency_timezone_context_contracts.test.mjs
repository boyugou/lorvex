import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

// urgency_score computation has been fully removed from both app and MCP
// runtimes (#1515). These contracts verify that urgency artifacts are gone
// and that no stale urgency code paths remain.

test('app runtime no longer contains urgency computation helpers', () => {
  const invariantsSource = readRustSources(
    'app/src-tauri/src/invariants.rs',
    'app/src-tauri/src/invariants',
  );
  const commandsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );

  assert.doesNotMatch(
    invariantsSource,
    /pub fn compute_urgency_score/,
    'app invariants should not contain urgency computation after removal',
  );
  assert.doesNotMatch(
    commandsSource,
    /compute_task_urgency_for_conn|compute_urgency_score/,
    'commands.rs should not re-export urgency helpers after removal',
  );
});

test('mcp runtime no longer contains urgency computation helpers', () => {
  const taskSupportSource = readRustSources(
    'mcp-server/src/tasks/support.rs',
    'mcp-server/src/tasks/support',
  );

  assert.doesNotMatch(
    taskSupportSource,
    /pub\(crate\) fn compute_urgency_score/,
    'server_task_support should not contain urgency computation after removal',
  );
  assert.doesNotMatch(
    taskSupportSource,
    /pub\(crate\) fn recompute_task_urgency\(/,
    'server_task_support should not contain recompute_task_urgency after removal',
  );
  assert.doesNotMatch(
    taskSupportSource,
    /mod urgency;/,
    'server_task_support should not declare an urgency submodule after removal',
  );
});
