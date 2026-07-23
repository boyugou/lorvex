import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

test('tauri db runtime is organized as a folder-backed subsystem with dedicated connection and path modules', () => {
  const staleMigrationsWrapperPath = path.join(repoRoot, 'app/src-tauri/src/db/migrations.rs');
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/db.rs'), 'utf8');
  const connectionSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/db/connection.rs'),
    'utf8',
  );
  const pathSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/db/path.rs'), 'utf8');
  const testsSource = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/db/tests.rs'), 'utf8');

  for (const moduleName of ['connection', 'path']) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.doesNotMatch(
    rootSource,
    /^mod seed;$/m,
    'db.rs should not retain a stale seed module after moving seeding elsewhere',
  );
  assert.doesNotMatch(rootSource, /^mod migrations;$/m);
  assert.equal(
    fs.existsSync(staleMigrationsWrapperPath),
    false,
    'app/src-tauri/src/db/migrations.rs should not linger as a dead wrapper after store-owned migration convergence',
  );
  assert.match(rootSource, /^#\[cfg\(test\)\]$/m);
  assert.match(rootSource, /^mod tests;$/m);
  assert.equal(
    hasRustUseReexport(rootSource, {
      modulePath: 'connection',
      symbols: ['get_conn', 'get_db', 'get_read_conn'],
    }),
    true,
    'db.rs should re-export the canonical writer/read connection accessors from connection.rs',
  );
  assert.equal(
    hasRustUseReexport(rootSource, {
      modulePath: 'path',
      symbols: ['db_path'],
    }),
    true,
    'db.rs should re-export db_path from path.rs',
  );
  assert.doesNotMatch(
    rootSource,
    /\npub fn get_conn\(|\npub fn get_db\(|\npub fn get_read_conn\(|\npub fn db_path\(/,
    'db.rs should stay a composition root after folder extraction',
  );

  assert.match(connectionSource, /pub fn get_conn\(/);
  assert.match(connectionSource, /pub fn get_db\(/);
  assert.match(connectionSource, /pub fn get_read_conn\(/);
  assert.match(pathSource, /pub fn db_path\(/);
  assert.match(connectionSource, /ConnectionPool::new\(/);
  assert.match(
    connectionSource,
    /use lorvex_store::ConnectionPool;[\s\S]*ConnectionPool::new\(/,
    'db connection should delegate schema initialization to lorvex_store instead of keeping an app-local migrations owner',
  );
  assert.match(
    testsSource,
    /use lorvex_store::migration::apply_migrations;[\s\S]*use lorvex_store::schema::all_migrations;/,
    'db tests should validate the canonical store-owned migration graph rather than an app-local wrapper',
  );
  assert.match(testsSource, /fn apply_migrations_creates_final_schema_from_empty_database\(/);
  assert.match(testsSource, /fn db_path_ignores_empty_db_path_env_override\(/);
  assert.match(testsSource, /fn db_path_trims_db_path_env_override\(/);
});
