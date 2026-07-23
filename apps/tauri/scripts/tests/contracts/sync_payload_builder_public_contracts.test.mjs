import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('sync payload builders expose a narrow explicit public surface', () => {
  const source = read('lorvex-store/src/payload_loaders/mod.rs');

  assert.doesNotMatch(
    source,
    /\npub use [a-z_]+::\*/,
    'sync_payload_builders must not wildcard-reexport private builder modules',
  );
  assert.match(
    source,
    /pub enum SimpleSyncSeedKind\b/,
    'sync_payload_builders should expose a typed seed kind API instead of raw row mappers',
  );
  assert.match(
    source,
    /pub fn for_each_simple_sync_payload\b/,
    'sync_payload_builders should own simple seed scans behind a callback API',
  );
});

test('Tauri sync seed orchestration does not depend on sync payload row internals', () => {
  const seedOrchestrator = read('app/src-tauri/src/commands/sync/runtime/queue/seed_orchestrator.rs');
  const seedEntities = read('app/src-tauri/src/commands/sync/runtime/queue/seed_entities.rs');
  const seedHelpers = read('app/src-tauri/src/commands/sync/runtime/queue/seed_helpers.rs');
  const combined = `${seedOrchestrator}\n${seedEntities}\n${seedHelpers}`;

  assert.doesNotMatch(
    combined,
    /sync_payload_builders as spb|spb::|_SELECT_COLUMNS|_payload_from_row|seed_via_builder/,
    'Tauri seed orchestration should use store-owned simple seed APIs, not SELECT columns or row mappers',
  );
  assert.match(
    combined,
    /for_each_simple_sync_payload/,
    'Tauri seed orchestration should call the store-owned simple sync payload scanner',
  );
});

