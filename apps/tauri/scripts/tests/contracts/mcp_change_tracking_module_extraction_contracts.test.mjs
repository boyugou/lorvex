import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('mcp changelog and sync-checkpoint helpers live in a dedicated change-tracking module', () => {
  const changeTrackingPath = path.join(repoRoot, 'mcp-server/src/runtime/change_tracking/mod.rs');
  const helpersSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/system/handler_support.rs'), 'utf8');
  const syncSource = readRustSources(
    'mcp-server/src/system/sync.rs',
    'mcp-server/src/system/sync',
  );
  const preferencesSource = readRustSources(
    'mcp-server/src/preferences/mod.rs',
    'mcp-server/src/preferences/storage.rs',
    'mcp-server/src/preferences/vocabulary.rs',
  );
  const preferencesUiSource = readRustSources(
    'mcp-server/src/preferences/ui/mod.rs',
    'mcp-server/src/preferences/ui/control.rs',
    'mcp-server/src/preferences/ui/parsing.rs',
  );
  // server_memory.rs has been split into server_memory/{mod,gate,write,delete,history,read,tests}.rs.
  // The change-tracking import that this contract pins lands in mod.rs / write.rs / delete.rs;
  // we read the full module tree so the contract accepts the import wherever the
  // refactor put it.
  const memorySource = readRustSources('mcp-server/src/memory');

  assert.ok(
    fs.existsSync(changeTrackingPath),
    'server_change_tracking.rs should exist as the dedicated home for changelog/sync-checkpoint helpers',
  );

  const changeTrackingRootSource = fs.readFileSync(changeTrackingPath, 'utf8');
  const changeTrackingSource = readRustSources(
    'mcp-server/src/runtime/change_tracking/mod.rs',
    'mcp-server/src/runtime/change_tracking',
  );

  for (const snippet of [
    'struct LogChangeParams',
    'fn resolve_ai_actor_name(',
    'fn dedupe_entity_ids(',
    'fn read_current_entity_snapshot(',
    'fn get_or_create_sync_device_id(',
    'fn log_change(',
  ]) {
    assert.doesNotMatch(
      helpersSource,
      new RegExp(snippet.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      `server_handler_support.rs should not keep change-tracking helper ${snippet}`,
    );
  }

  for (const moduleName of ['hlc', 'log_change', 'outbox', 'relations', 'retention', 'snapshot']) {
    assert.match(changeTrackingRootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  for (const exportLine of [
    /^pub\(crate\) use hlc::\{generate_hlc_version, with_hlc_session\};$/m,
    /^pub\(crate\) use log_change::\{log_change, write_preview_audit_entry, LogChangeParams\};$/m,
  ]) {
    assert.match(
      changeTrackingRootSource,
      exportLine,
      'server_change_tracking.rs should keep a stable facade over change-tracking support modules',
    );
  }
  assert.doesNotMatch(
    changeTrackingRootSource,
    /\npub\(crate\) struct LogChangeParams \{|\npub\(crate\) fn log_change\(|\npub\(crate\) fn get_sync_checkpoint_value\(/,
    'server_change_tracking.rs should keep heavyweight change logging in focused modules',
  );
  for (const snippet of [
    'pub(crate) struct LogChangeParams',
    'pub(crate) fn resolve_ai_actor_name(',
    'pub(crate) fn get_or_create_sync_device_id(',
    'pub(crate) fn log_change(',
  ]) {
    assert.match(
      changeTrackingSource,
      new RegExp(snippet.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      `server_change_tracking module tree should own ${snippet}`,
    );
  }
  assert.doesNotMatch(
    syncSource,
    /get_sync_checkpoint_value/,
    'server_sync should read sync status through the shared store snapshot instead of a bespoke checkpoint helper',
  );
  assert.match(
    preferencesSource + '\n' + preferencesUiSource,
    /use crate::runtime::change_tracking::\{[\s\S]*log_change[\s\S]*LogChangeParams[\s\S]*}/,
    'preference modules should import change-tracking helpers from the dedicated module',
  );
  assert.match(
    preferencesUiSource,
    /use crate::runtime::change_tracking::\{log_change, resolve_ai_actor_name, LogChangeParams\};/,
    'assistant UI preference control should import the actor helper from the change-tracking module',
  );
  assert.match(
    memorySource,
    /use crate::runtime::change_tracking::\{[\s\S]*log_change[\s\S]*LogChangeParams[\s\S]*}/,
    'server_memory.rs should import changelog helpers from the dedicated module',
  );
});
