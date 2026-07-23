import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('server_contract delegates defaults and root-only tests to focused helper modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/contract.rs'), 'utf8');
  const supportSource = readRustSources(
    'mcp-server/src/contract/defaults.rs',
    'mcp-server/src/contract/tests.rs',
  );

  assert.match(rootSource, /^mod defaults;$/m);
  assert.match(rootSource, /^pub\(crate\) use defaults::\*;$/m);
  assert.match(rootSource, /^mod tests;$/m);
  assert.equal(
    fs.existsSync(path.join(repoRoot, 'mcp-server/src/contract/serde_support.rs')),
    false,
    'nullable patch semantics should stay centralized in lorvex_domain::Patch instead of an MCP-local serde helper',
  );

  assert.doesNotMatch(
    rootSource,
    /\n(?:const )?fn deserialize_nullable<'de, T, D>\(|\n(?:const )?fn default_status_open\(|\n(?:const )?fn default_status_all\(|\n(?:const )?fn default_calendar_events_limit\(|\n(?:const )?fn default_list_tasks_limit\(|\n(?:const )?fn create_calendar_event_args_reject_string_all_day\(/,
    'server_contract root should keep default helpers and root-only tests out of the facade',
  );

  assert.match(supportSource, /\npub\(crate\) (?:const )?fn default_status_open\(/);
  assert.match(supportSource, /\npub\(crate\) (?:const )?fn default_status_all\(/);
  assert.match(supportSource, /\npub\(crate\) (?:const )?fn default_calendar_events_limit\(/);
  assert.match(supportSource, /\n(?:const )?fn create_calendar_event_args_reject_string_all_day\(/);
});
