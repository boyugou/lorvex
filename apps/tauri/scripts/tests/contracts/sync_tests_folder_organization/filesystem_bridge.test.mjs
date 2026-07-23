import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';

test('sync filesystem-bridge tests are organized as focused cursor, collection, and filesystem-root modules', () => {
  const syncTestsDir = path.join(repoRoot, 'app/src-tauri/src/commands/tests/sync');
  const fileBridgeDir = path.join(syncTestsDir, 'filesystem_bridge');
  const fileBridgeRoot = fs.readFileSync(path.join(fileBridgeDir, 'mod.rs'), 'utf8');
  const fileBridgeCursorSource = fs.readFileSync(path.join(fileBridgeDir, 'cursor.rs'), 'utf8');
  const fileBridgeCollectionOrderingSource = fs.readFileSync(path.join(fileBridgeDir, 'collection_ordering.rs'), 'utf8');
  const fileBridgeCollectionFilteringSource = fs.readFileSync(path.join(fileBridgeDir, 'collection_filtering.rs'), 'utf8');
  const fileBridgeCollectionLookbackSource = fs.readFileSync(path.join(fileBridgeDir, 'collection_lookback.rs'), 'utf8');
  const fileBridgeCollectionDelayedSource = fs.readFileSync(path.join(fileBridgeDir, 'collection_delayed.rs'), 'utf8');
  const fileBridgeRootPathSource = fs.readFileSync(path.join(fileBridgeDir, 'filesystem_bridge_root_path.rs'), 'utf8');

  for (const moduleName of ['collection_delayed', 'collection_filtering', 'collection_lookback', 'collection_ordering']) {
    assert.match(
      fileBridgeRoot,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `filesystem_bridge/mod.rs should register ${moduleName}`,
    );
  }
  assert.match(fileBridgeRoot, /^mod cursor;$/m, 'filesystem_bridge/mod.rs should register the cursor test module');
  assert.match(fileBridgeRoot, /^mod filesystem_bridge_root_path;$/m, 'filesystem_bridge/mod.rs should register the filesystem_bridge_root_path test module');
  assert.equal(
    fs.existsSync(path.join(syncTestsDir, 'filesystem_bridge.rs')),
    false,
    'commands/tests/sync/filesystem_bridge.rs should be replaced by a filesystem_bridge/ folder tree',
  );
  for (const testName of [
    'load_filesystem_bridge_pull_cursor_rejects_malformed_state',
    'store_filesystem_bridge_pull_cursor_is_monotonic',
    'store_filesystem_bridge_pull_cursor_rejects_empty_fields',
  ]) {
    assert.match(
      fileBridgeCursorSource,
      new RegExp(`fn ${testName}\\(`),
      `filesystem_bridge/cursor.rs should cover ${testName}`,
    );
  }

  assert.equal(
    fs.existsSync(path.join(fileBridgeDir, 'collection.rs')),
    false,
    'commands/tests/sync/filesystem_bridge/collection.rs should be replaced by flat collection_* modules',
  );
  for (const testName of [
    'collect_remote_filesystem_bridge_envelopes_is_deterministic_under_pull_cap',
    'collect_remote_filesystem_bridge_envelopes_under_pull_cap_progresses_without_skipping_backlog',
  ]) {
    assert.match(
      fileBridgeCollectionOrderingSource,
      new RegExp(`fn ${testName}\\(`),
      `filesystem_bridge/collection_ordering.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'collect_remote_filesystem_bridge_envelopes_accounts_parse_errors_and_local_filter',
    'collect_remote_filesystem_bridge_envelopes_applies_filesystem_bridge_cursor_filtering',
  ]) {
    assert.match(
      fileBridgeCollectionFilteringSource,
      new RegExp(`fn ${testName}\\(`),
      `filesystem_bridge/collection_filtering.rs should cover ${testName}`,
    );
  }
  for (const testName of [
    'collect_remote_filesystem_bridge_envelopes_includes_delayed_event_within_cursor_lookback',
    'collect_remote_filesystem_bridge_envelopes_lookback_skips_known_event_ids',
  ]) {
    assert.match(
      fileBridgeCollectionLookbackSource,
      new RegExp(`fn ${testName}\\(`),
      `filesystem_bridge/collection_lookback.rs should cover ${testName}`,
    );
  }
  assert.match(
    fileBridgeCollectionDelayedSource,
    /fn delayed_event_at_or_behind_cursor_is_accounted_as_stale_when_newer_entity_exists\(/,
    'filesystem_bridge/collection_delayed.rs should own delayed stale-apply accounting regressions',
  );
  for (const testName of [
    'resolve_filesystem_bridge_root_path_rejects_empty',
    'resolve_filesystem_bridge_root_path_expands_home_prefix',
  ]) {
    assert.match(
      fileBridgeRootPathSource,
      new RegExp(`fn ${testName}\\(`),
      `filesystem_bridge/filesystem_bridge_root_path.rs should cover ${testName}`,
    );
  }
});
