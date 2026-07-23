import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('MCP tool contracts require canonical booleans instead of boolish compatibility coercion', () => {
  const contractText = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/contract.rs'), 'utf8');
  const setupGuide = fs.readFileSync(path.join(repoRoot, 'docs/setup/ASSISTANT_MCP_SETUP.md'), 'utf8');

  assert.doesNotMatch(
    contractText,
    /deserialize_option_boolish|option_boolish_schema|Accepts boolean or string "true"\/"false"/,
    'server_contract.rs should not keep boolish compatibility deserializers or docs once MCP booleans are canonical',
  );
  assert.doesNotMatch(
    setupGuide,
    /Safe representation coercions may exist|do not rely on coercion|compatibility fallback/,
    'assistant MCP setup should not describe tolerated representation coercions after strict contract cleanup',
  );
});
