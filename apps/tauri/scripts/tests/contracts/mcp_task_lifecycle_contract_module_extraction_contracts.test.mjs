import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_contract task module delegates lifecycle and recurrence schemas to a dedicated task/lifecycle submodule', () => {
  // task.rs has been split into task/{mod, ...}. The lifecycle facade lives
  // in task/mod.rs now.
  const taskModulePath = path.join(repoRoot, 'mcp-server/src/contract/task/mod.rs');
  const taskModuleSource = fs.readFileSync(taskModulePath, 'utf8');
  const lifecycleModulePath = path.join(
    repoRoot,
    'mcp-server/src/contract/task/lifecycle.rs',
  );

  assert.ok(
    fs.existsSync(lifecycleModulePath),
    'server_contract/task/lifecycle.rs should exist as the dedicated home for task lifecycle and recurrence contracts',
  );

  const lifecycleModuleSource = fs.readFileSync(lifecycleModulePath, 'utf8');

  assert.match(
    taskModuleSource,
    /mod lifecycle;/,
    'server_contract/task.rs should declare a dedicated lifecycle contract submodule',
  );
  assert.match(
    taskModuleSource,
    /pub\(crate\) use lifecycle::\{/,
    'server_contract/task.rs should re-export lifecycle contracts explicitly through the task facade',
  );

  for (const symbol of [
    'RecurrenceFreq',
    'SetRecurrenceArgs',
    'SetTaskAiNotesArgs',
    'CompleteTaskArgs',
    'CancelTaskArgs',
    'PermanentDeleteTaskArgs',
  ]) {
    assert.match(
      lifecycleModuleSource,
      new RegExp(`\\b${symbol}\\b`),
      `server_contract/task/lifecycle.rs should own ${symbol}`,
    );
    assert.doesNotMatch(
      taskModuleSource,
      new RegExp(`\\bstruct ${symbol}\\b|\\benum ${symbol}\\b`),
      `server_contract/task.rs should not keep inline ${symbol} definitions after extraction`,
    );
  }
});
