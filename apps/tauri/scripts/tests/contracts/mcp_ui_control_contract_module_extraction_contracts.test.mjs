import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_contract keeps UI control schemas in a dedicated ui_control module behind the root facade', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/contract.rs'),
    'utf8',
  );
  const uiControlModulePath = path.join(repoRoot, 'mcp-server/src/contract/ui_control/mod.rs');
  const uiControlModuleSource = fs.readFileSync(uiControlModulePath, 'utf8');

  assert.match(
    rootSource,
    /mod ui_control;/,
    'server_contract.rs should declare a dedicated ui_control contract submodule',
  );
  assert.match(
    rootSource,
    /pub\(crate\) use ui_control::\*;/,
    'server_contract.rs should re-export UI control contracts so downstream code keeps one import surface',
  );

  for (const symbol of ['UiAction', 'ControlAppUiArgs', 'UiCommandMetadata']) {
    assert.match(
      uiControlModuleSource,
      new RegExp(`\\b${symbol}\\b`),
      `server_contract/ui_control.rs should own ${symbol}`,
    );
    assert.doesNotMatch(
      rootSource,
      new RegExp(`\\bstruct ${symbol}\\b|\\benum ${symbol}\\b`),
      `server_contract.rs should not keep inline ${symbol} definitions after extraction`,
    );
  }
});
