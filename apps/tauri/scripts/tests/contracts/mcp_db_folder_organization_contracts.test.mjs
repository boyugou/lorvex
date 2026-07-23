import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

test('mcp db runtime is organized as a folder-backed subsystem with dedicated connection and path modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/db.rs'), 'utf8');
  const connectionSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/db/connection.rs'),
    'utf8',
  );
  const pathSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/db/path.rs'), 'utf8');
  const testsSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/db/tests.rs'), 'utf8');

  for (const moduleName of ['connection', 'path']) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.match(rootSource, /^#\[cfg\(test\)\]$/m);
  assert.match(rootSource, /^mod tests;$/m);
  assert.equal(
    hasRustUseReexport(rootSource, {
      modulePath: 'connection',
      symbols: ['open_database_for_path'],
    }),
    true,
    'db.rs should re-export open_database_for_path from connection.rs',
  );
  assert.equal(
    hasRustUseReexport(rootSource, {
      modulePath: 'path',
      symbols: ['resolve_db_path'],
    }),
    true,
    'db.rs should re-export resolve_db_path from path.rs',
  );
  assert.doesNotMatch(
    rootSource,
    /\npub fn open_database_for_path\(|\npub fn resolve_db_path\(/,
    'db.rs should stay a composition root after folder extraction',
  );

  assert.match(connectionSource, /pub fn open_database_for_path\(/);
  assert.match(connectionSource, /lorvex_store::migration::apply_migrations/);
  assert.match(connectionSource, /lorvex_store::schema::all_migrations/);
  assert.match(pathSource, /pub fn resolve_db_path\(/);
  assert.equal(
    fs.existsSync(path.join(repoRoot, 'mcp-server/src/db/migrations.rs')),
    false,
    'migrations should stay delegated to lorvex-store instead of a parallel MCP-local module',
  );
  assert.match(testsSource, /fn resolve_db_path_prefers_env_var\(/);
  assert.match(testsSource, /fn resolve_db_path_trims_env_var\(/);
});
