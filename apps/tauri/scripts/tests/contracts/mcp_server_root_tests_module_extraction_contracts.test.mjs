import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('mcp server root keeps root-specific tests in a dedicated tests module file', () => {
  // After server.rs → server/{mod, ...}, the root file is server/mod.rs.
  // It must declare the tests module via a bare `#[cfg(test)] mod tests;`
  // (not an inline block) so the tests/ module tree owns the scaffolding.
  const serverModSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/server/mod.rs'),
    'utf8',
  );
  const testsSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/server/tests/mod.rs'),
    'utf8',
  );

  assert.match(serverModSource, /#\[cfg\(test\)\]\s*\nmod tests;/);
  assert.doesNotMatch(
    serverModSource,
    /#\[cfg\(test\)\]\s*\nmod tests\s*\{/,
    'server/mod.rs should not inline the root tests module after extraction',
  );
  assert.equal(
    fs.existsSync(path.join(repoRoot, 'mcp-server/src/server/tests.rs')),
    false,
    'server/tests.rs should be replaced by a tests/ module tree',
  );
  assert.match(
    testsSource,
    /fn make_server\(\) -> TestServer[\s\S]*fn seed_list_named\([\s\S]*fn seed_task\(/,
    'server/tests/mod.rs should own the migrated root test support and scaffolding',
  );
});
