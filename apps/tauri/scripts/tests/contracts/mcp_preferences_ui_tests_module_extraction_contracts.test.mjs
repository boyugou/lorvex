import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('assistant UI runtime keeps inline tests in a dedicated tests module file', () => {
  const modulePath = path.join(repoRoot, 'mcp-server/src/preferences/ui/mod.rs');
  const testsPath = path.join(repoRoot, 'mcp-server/src/preferences/ui/tests/mod.rs');

  const moduleSource = fs.readFileSync(modulePath, 'utf8');

  assert.ok(fs.existsSync(testsPath), 'server_preferences_ui/tests/mod.rs should exist');
  assert.match(
    moduleSource,
    /#\[cfg\(test\)\]\s*mod tests;/,
    'server_preferences_ui/mod.rs should route tests through a dedicated tests module tree',
  );
  assert.doesNotMatch(
    moduleSource,
    /#\[cfg\(test\)\]\s*mod tests \{/,
    'server_preferences_ui/mod.rs should not keep an inline tests block after extraction',
  );
});
