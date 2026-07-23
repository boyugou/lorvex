import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_contract keeps preference and setup schemas in a dedicated preferences module behind the root facade', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/contract.rs'),
    'utf8',
  );
  const preferencesModulePath = path.join(repoRoot, 'mcp-server/src/contract/preferences.rs');
  const preferencesModuleSource = fs.readFileSync(preferencesModulePath, 'utf8');

  assert.match(
    rootSource,
    /mod preferences;/,
    'server_contract.rs should declare a dedicated preferences contract submodule',
  );
  assert.match(
    rootSource,
    /pub\(crate\) use preferences::\*;/,
    'server_contract.rs should re-export preferences contracts so downstream code keeps one import surface',
  );

  for (const symbol of ['GetPreferenceArgs', 'SetPreferenceArgs', 'CompleteSetupArgs']) {
    assert.match(
      preferencesModuleSource,
      new RegExp(`\\b${symbol}\\b`),
      `server_contract/preferences.rs should own ${symbol}`,
    );
    assert.doesNotMatch(
      rootSource,
      new RegExp(`\\bstruct ${symbol}\\b|\\benum ${symbol}\\b`),
      `server_contract.rs should not keep inline ${symbol} definitions after extraction`,
    );
  }
});
