import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { hasRustUseReexport, readRustSources, repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

const commandsPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands.rs');
const syncFilesystemBridgePath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands', 'sync', 'filesystem_bridge.rs');
const syncFilesystemBridgeDir = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands', 'sync', 'filesystem_bridge');
const syncFilesystemBridgeRuntimeDir = path.join(syncFilesystemBridgeDir, 'runtime');

test('commands root delegates filesystem-bridge sync runtime to a dedicated module', () => {
  const source = fs.readFileSync(commandsPath, 'utf8');
  const rootSource = fs.readFileSync(syncFilesystemBridgePath, 'utf8');
  const collectionSource = fs.readFileSync(path.join(syncFilesystemBridgeDir, 'collection.rs'), 'utf8');
  const cursorSource = fs.readFileSync(path.join(syncFilesystemBridgeDir, 'cursor.rs'), 'utf8');
  const runtimeRootSource = fs.readFileSync(path.join(syncFilesystemBridgeRuntimeDir, 'mod.rs'), 'utf8');
  const runtimeTestsFacadeSource = runtimeRootSource;
  const runtimeCommandSource = fs.readFileSync(path.join(syncFilesystemBridgeRuntimeDir, 'command.rs'), 'utf8');
  const runtimeOrchestrationSource = fs.readFileSync(path.join(syncFilesystemBridgeRuntimeDir, 'orchestration.rs'), 'utf8');
  const runtimeSource = readRustSources('app/src-tauri/src/commands/sync/filesystem_bridge/runtime');
  const legacyRuntimePath = path.join(syncFilesystemBridgeDir, 'runtime.rs');

  assert.match(source, rustModuleDeclarationPattern('sync'));
  assert.doesNotMatch(
    source,
    /pub use sync::filesystem_bridge::\{run_filesystem_bridge_sync, FilesystemBridgeSyncResult\}/,
    'commands.rs should not keep filesystem-bridge IPC re-exports for handler registration',
  );

  assert.match(rootSource, rustModuleDeclarationPattern('collection'));
  assert.match(rootSource, rustModuleDeclarationPattern('cursor'));
  assert.match(rootSource, rustModuleDeclarationPattern('runtime'));
  assert.match(rootSource, /^#\[cfg\(test\)\]\s*$/m);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'collection',
    symbols: 'collect_remote_filesystem_bridge_envelopes',
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub(crate)',
    modulePath: 'cursor',
    symbols: [
      'load_filesystem_bridge_pull_cursor',
      'newest_filesystem_bridge_pull_cursor',
      'store_filesystem_bridge_pull_cursor',
      'FilesystemBridgePullCursor',
    ],
  }), true);
  assert.equal(hasRustUseReexport(rootSource, {
    visibility: 'pub',
    modulePath: 'runtime',
    symbols: ['run_filesystem_bridge_sync', 'FilesystemBridgeSyncResult'],
  }), true);
  assert.doesNotMatch(
    rootSource,
    /\nfn within_filesystem_bridge_cursor_lookback\(|\nstruct CollectedRemoteFilesystemBridgeEnvelopes|\nfn load_recent_lookback_outbox_ids\(|\npub fn run_filesystem_bridge_sync\(|\npub struct FilesystemBridgeSyncResult/,
    'sync_filesystem_bridge root should stay a facade after folder extraction',
  );

  assert.match(collectionSource, /fn within_filesystem_bridge_cursor_lookback\(/);
  assert.match(collectionSource, /struct CollectedRemoteFilesystemBridgeEnvelopes \{/);
  assert.match(collectionSource, /fn collect_remote_filesystem_bridge_envelopes\(/);
  assert.match(collectionSource, /fn load_recent_lookback_outbox_ids\(/);
  assert.match(cursorSource, /struct FilesystemBridgePullCursor \{/);
  assert.match(cursorSource, /fn load_filesystem_bridge_pull_cursor\(/);
  assert.match(cursorSource, /fn store_filesystem_bridge_pull_cursor\(/);
  assert.match(cursorSource, /fn newest_filesystem_bridge_pull_cursor\(/);

  assert.equal(
    fs.existsSync(legacyRuntimePath),
    false,
    'sync_filesystem_bridge/runtime.rs should stay replaced by a folder-backed runtime subtree',
  );
  assert.deepEqual(
    fs
      .readdirSync(syncFilesystemBridgeRuntimeDir)
      .filter((fileName) => fileName.endsWith('.rs'))
      .sort(),
    [
      'backoff.rs',
      'command.rs',
      'finalize.rs',
      'lease.rs',
      'mod.rs',
      'naming.rs',
      'orchestration.rs',
      'push.rs',
      'result.rs',
      'tests_backoff.rs',
      'tests_classifier.rs',
      'tests_finalize.rs',
      'tests_gc.rs',
      'tests_heartbeat.rs',
      'tests_naming.rs',
      'tests_push.rs',
      'tests_read_state.rs',
      'tests_roundtrip.rs',
      'tests_support.rs',
    ],
    'sync_filesystem_bridge runtime module file set drifted',
  );
  for (const moduleName of [
    'backoff',
    'command',
    'finalize',
    'lease',
    'naming',
    'orchestration',
    'push',
    'result',
  ]) {
    assert.match(runtimeRootSource, rustModuleDeclarationPattern(moduleName));
  }
  for (const moduleName of [
    'tests_backoff',
    'tests_classifier',
    'tests_finalize',
    'tests_gc',
    'tests_heartbeat',
    'tests_naming',
    'tests_push',
    'tests_read_state',
    'tests_roundtrip',
    'tests_support',
  ]) {
    assert.match(
      runtimeRootSource,
      new RegExp(`^#\\[cfg\\(test\\)\\]\\s*(?:pub\\(crate\\)\\s+)?mod\\s+${moduleName};$`, 'm'),
    );
  }
  assert.match(runtimeRootSource, /^pub use command::run_filesystem_bridge_sync;$/m);
  assert.match(runtimeRootSource, /^pub use result::FilesystemBridgeSyncResult;$/m);
  assert.doesNotMatch(
    runtimeRootSource,
    /\n(?:pub(?:\([^)]+\))?\s+)?(?:async\s+)?fn\s|\n(?:pub(?:\([^)]+\))?\s+)?struct\s|\n(?:pub(?:\([^)]+\))?\s+)?enum\s/,
    'sync_filesystem_bridge/runtime/mod.rs should stay a pure facade after runtime extraction',
  );
  assert.doesNotMatch(
    runtimeSource,
    /target_os = "macos"|target_os = "ios"/,
    'filesystem bridge runtime is cross-platform and must not inherit Remote provider Apple-only cfg gates',
  );
  assert.match(runtimeSource, /pub struct FilesystemBridgeSyncResult \{/);
  assert.match(runtimeSource, /pub fn run_filesystem_bridge_sync\(/);
  assert.match(runtimeSource, /fn run_filesystem_bridge_sync_command\(/);
  assert.match(runtimeSource, /fn run_filesystem_bridge_sync_inner\(/);
  assert.match(runtimeSource, /fn phase_read_outbox_and_pull_state\(/);
  assert.match(runtimeSource, /fn phase_push_to_filesystem\(/);
  assert.match(runtimeSource, /fn phase_record_push_results\(/);
  assert.match(runtimeSource, /fn phase_apply_and_finalize\(/);
  assert.match(runtimeSource, /fn renew_filesystem_bridge_lease_or_abort\(/);
  assert.match(runtimeSource, /fn apply_incoming_via_envelope\(/);
  assert.match(runtimeSource, /fn gc_stale_sync_files\(/);
  assert.match(runtimeSource, /fn filesystem_bridge_file_stem\(/);
  for (const moduleName of [
    'tests_backoff',
    'tests_classifier',
    'tests_finalize',
    'tests_gc',
    'tests_heartbeat',
    'tests_naming',
    'tests_push',
    'tests_read_state',
    'tests_roundtrip',
  ]) {
    assert.match(runtimeTestsFacadeSource, rustModuleDeclarationPattern(moduleName));
  }
  assert.doesNotMatch(
    runtimeTestsFacadeSource,
    /#\[test\]|(?:^|\n)\s*mod\s+\w+\s*\{/,
    'runtime/tests.rs should stay a fixture facade over focused runtime test modules',
  );
  assert.match(
    runtimeCommandSource,
    /try_acquire_sync_owner_with_guard_now\([\s\S]*FILESYSTEM_BRIDGE_SYNC_LEASE_NAME[\s\S]*desktop_app_sync_owner_id\(\)[\s\S]*SYNC_OWNER_LEASE_TTL_MS[\s\S]*release_sync_owner/,
    'filesystem bridge command must keep lease acquisition and release wiring in the command path',
  );
  assert.match(
    runtimeCommandSource,
    /\}; \/\/ conn dropped — writer released before sync I\/O[\s\S]*run_filesystem_bridge_sync_inner/,
    'filesystem bridge command must release its writer connection before sync I/O orchestration',
  );
  assert.match(
    runtimeOrchestrationSource,
    /phase_read_outbox_and_pull_state[\s\S]*refresh_dispatchable_pending_outbox[\s\S]*phase_push_to_filesystem[\s\S]*renew_filesystem_bridge_lease_or_abort[\s\S]*phase_record_push_results[\s\S]*collect_remote_filesystem_bridge_envelopes[\s\S]*phase_apply_and_finalize/s,
    'filesystem bridge orchestration must preserve short-lived DB phase boundaries and lease renewals',
  );
});
