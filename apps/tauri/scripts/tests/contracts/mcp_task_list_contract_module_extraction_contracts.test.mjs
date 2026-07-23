import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_contract task module delegates list-oriented schemas to a dedicated task/lists submodule', () => {
  // task.rs has been split into task/{mod, ...}. The list-facade declarations
  // live in task/mod.rs now.
  const taskModulePath = path.join(repoRoot, 'mcp-server/src/contract/task/mod.rs');
  const taskModuleSource = fs.readFileSync(taskModulePath, 'utf8');
  const listModulePath = path.join(repoRoot, 'mcp-server/src/contract/task/lists.rs');

  assert.ok(
    fs.existsSync(listModulePath),
    'server_contract/task/lists.rs should exist as the dedicated home for list-oriented task contracts',
  );

  const listModuleSource = fs.readFileSync(listModulePath, 'utf8');

  assert.match(
    taskModuleSource,
    /mod lists;/,
    'server_contract/task.rs should declare a dedicated lists contract submodule',
  );
  assert.match(
    taskModuleSource,
    /pub\(crate\) use lists::\*;/,
    'server_contract/task.rs should re-export list contracts through the task facade',
  );

  for (const symbol of [
    'CreateListArgs',
    'UpdateListArgs',
    'ReorganizeListStrategy',
    'ReorganizeListArgs',
    'DeleteListArgs',
    'BatchCancelTasksInListArgs',
    'GetListArgs',
    'GetListHealthSnapshotArgs',
  ]) {
    assert.match(
      listModuleSource,
      new RegExp(`\\b${symbol}\\b`),
      `server_contract/task/lists.rs should own ${symbol}`,
    );
    assert.doesNotMatch(
      taskModuleSource,
      new RegExp(`\\bstruct ${symbol}\\b|\\benum ${symbol}\\b`),
      `server_contract/task.rs should not keep inline ${symbol} definitions after extraction`,
    );
  }
});
