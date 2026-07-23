import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_contract task module delegates read/query schemas to a dedicated task/queries submodule', () => {
  // task.rs has been split into task/{mod, ...}. The query-facade declarations
  // live in task/mod.rs now.
  const taskModulePath = path.join(repoRoot, 'mcp-server/src/contract/task/mod.rs');
  const taskModuleSource = fs.readFileSync(taskModulePath, 'utf8');
  const queryModulePath = path.join(repoRoot, 'mcp-server/src/contract/task/queries.rs');

  assert.ok(
    fs.existsSync(queryModulePath),
    'server_contract/task/queries.rs should exist as the dedicated home for task read/query contracts',
  );

  const queryModuleSource = fs.readFileSync(queryModulePath, 'utf8');

  assert.match(
    taskModuleSource,
    /mod queries;/,
    'server_contract/task.rs should declare a dedicated queries contract submodule',
  );
  assert.match(
    taskModuleSource,
    /pub\(crate\) use queries::\{/,
    'server_contract/task.rs should re-export query contracts explicitly through the task facade',
  );

  for (const symbol of [
    'GetTaskArgs',
    'TaskStatusFilter',
    'ListTasksDueRangeArgs',
    'ListTasksArgs',
    'GetTodaysTasksArgs',
    'GetUpcomingTasksArgs',
    'SearchTasksArgs',
    'GetDeferredTasksArgs',
  ]) {
    assert.match(
      queryModuleSource,
      new RegExp(`\\b${symbol}\\b`),
      `server_contract/task/queries.rs should own ${symbol}`,
    );
    assert.doesNotMatch(
      taskModuleSource,
      new RegExp(`\\bstruct ${symbol}\\b|\\benum ${symbol}\\b`),
      `server_contract/task.rs should not keep inline ${symbol} definitions after extraction`,
    );
  }
});
