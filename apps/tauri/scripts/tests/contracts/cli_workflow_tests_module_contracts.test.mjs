import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const WORKFLOW = 'lorvex-cli/src/commands/workflow/mod.rs';
const TESTS = 'lorvex-cli/src/commands/workflow/tests.rs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('CLI workflow command tests live in a sibling tests module', () => {
  const workflowSource = read(WORKFLOW);
  const testsSource = read(TESTS);

  assert.match(
    workflowSource,
    /^#\[cfg\(test\)\]\s*mod tests;$/m,
    'workflow.rs should route tests through a sibling tests.rs module',
  );
  assert.doesNotMatch(
    workflowSource,
    /^#\[cfg\(test\)\]\s*mod tests \{$/m,
    'workflow.rs should not keep an inline tests block after extraction',
  );
  assert.ok(
    workflowSource.split('\n').length <= 780,
    'workflow.rs should shrink after moving inline tests out',
  );
  assert.match(
    testsSource,
    /fn map_public_api_error_decodes_structured_validation_payload\(/,
    'workflow/tests.rs should own structured MCP error mapping tests',
  );
  assert.match(
    testsSource,
    /fn run_batch_create_dry_run_does_not_persist_rows\(/,
    'workflow/tests.rs should own mutation wrapper integration tests',
  );
});
