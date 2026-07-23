import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('canonical priority docs and contracts use importance-first wording instead of legacy urgency labels', () => {
  const serverContractSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/contract.rs'),
    'utf8',
  );
  const serverTaskQueryContractSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/contract/task/queries.rs'),
    'utf8',
  );
  const dataModelSource = fs.readFileSync(
    path.join(repoRoot, 'docs/design/DATA_MODEL.md'),
    'utf8',
  );
  const invariantValidationSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/invariants/validation/mod.rs'),
    'utf8',
  );

  assert.match(
    serverContractSource,
    /importance-first, not urgency-first/,
    'MCP task priority contract should describe priority as importance-first',
  );
  assert.match(
    serverTaskQueryContractSource,
    /importance-first, not urgency-first/,
    'task query schema should describe numeric priority filters without legacy urgency labels',
  );
  assert.match(
    dataModelSource,
    /importance band\. Importance-first, not urgency-first/,
    'data model should describe priority as an importance band',
  );
  // The Tauri invariant validator now sources the allow-list display
  // string from `lorvex_domain::validation::TASK_PRIORITY_ALLOWED_VALUES_DISPLAY`
  // (literally "1|2|3"), keeping wording in lockstep with the MCP
  // server contract instead of duplicating "1, 2, or 3 (importance bands)".
  assert.match(
    invariantValidationSource,
    /Invalid priority '\{p\}'\. Expected one of: \{TASK_PRIORITY_ALLOWED_VALUES_DISPLAY\}/,
    'Tauri invariant errors should reuse the shared importance-band display constant',
  );

  for (const source of [
    serverContractSource,
    serverTaskQueryContractSource,
    dataModelSource,
    invariantValidationSource,
  ]) {
    assert.doesNotMatch(
      source,
      /1=urgent 2=high 3=medium 4=low|1 \(urgent\), 2 \(high\), 3 \(medium\), or 4 \(low\)|1\|2\|3\|4/,
      'canonical docs/contracts should not retain the old four-band urgency vocabulary',
    );
  }
});
