import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('server_sync is organized as a folder-backed subsystem with status runtime and dedicated tests module tree', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/system/sync.rs'), 'utf8');
  const statusRootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/sync/status/mod.rs'),
    'utf8',
  );
  const statusSource = readRustSources(
    'mcp-server/src/system/sync/status/mod.rs',
    'mcp-server/src/system/sync/status',
  );
  const testsRootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/system/sync/tests/mod.rs'),
    'utf8',
  );
  const testsSource = readRustSources(
    'mcp-server/src/system/sync/tests/mod.rs',
    'mcp-server/src/system/sync/tests',
  );

  assert.match(rootSource, /^mod status;$/m);
  assert.match(rootSource, /^#\[cfg\(test\)\]$/m);
  assert.match(rootSource, /^mod tests;$/m);
  assert.match(
    rootSource,
    /^pub\(crate\) use status::\{get_sync_status, list_pending_outbox_entries\};$/m,
  );
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn get_sync_status\(|\npub\(crate\) fn list_pending_outbox_entries\(|\n#\[cfg\(test\)\]\nmod tests \{/,
    'server_sync root should remain a composition root after folder extraction',
  );
  assert.match(statusRootSource, /^mod pending_events;$/m);
  assert.match(statusRootSource, /^mod snapshot;$/m);
  assert.match(
    statusRootSource,
    /^pub\(crate\) use pending_events::list_pending_outbox_entries;$/m,
  );
  assert.match(statusRootSource, /^pub\(crate\) use snapshot::get_sync_status;$/m);
  for (const fileName of ['pending_events.rs', 'snapshot.rs']) {
    assert.ok(
      fs.existsSync(path.join(repoRoot, 'mcp-server/src/system/sync/status', fileName)),
      `server_sync/status should include ${fileName}`,
    );
  }
  assert.match(statusSource, /\npub\(crate\) fn get_sync_status\(/);
  assert.match(statusSource, /\npub\(crate\) fn list_pending_outbox_entries\(/);
  assert.doesNotMatch(testsRootSource, /^mod cloudkit_cursor;$/m);
  assert.match(testsRootSource, /^mod filesystem_bridge_cursor;$/m);
  assert.match(testsRootSource, /^mod malformed_state;$/m);
  assert.match(testsRootSource, /^mod shared;$/m);
  assert.match(testsRootSource, /^mod steady_state;$/m);
  assert.match(testsRootSource, /^mod timestamps;$/m);
  for (const fileName of ['filesystem_bridge_cursor.rs', 'malformed_state.rs', 'shared.rs', 'steady_state.rs', 'timestamps.rs']) {
    assert.ok(
      fs.existsSync(path.join(repoRoot, 'mcp-server/src/system/sync/tests', fileName)),
      `server_sync/tests should include ${fileName}`,
    );
  }
  assert.match(testsSource, /\n(?:pub\(super\)\s+)?fn setup_sync_status_test_conn\(/);
  assert.doesNotMatch(testsSource, /get_sync_status_surfaces_cloudkit_cursor_state/);
  assert.match(
    testsSource,
    /\nfn get_sync_status_flags_invalid_filesystem_bridge_cursor_timestamp_as_malformed\(/,
  );
  assert.match(testsSource, /\nfn get_sync_status_surfaces_pending_inbox_depth_and_oldest_attempt\(/);
  assert.match(testsSource, /\nfn get_sync_status_trims_valid_timestamp_state\(/);
});
