#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  missingLocaleCatalogKeys,
  readLocaleCatalog,
  readStrictParityLocaleCodes,
} from '../lib/ui_wiring_contract_support.mjs';

function fail(message) {
  console.error(`[verify:sync-filesystem-bridge-cursor-contract] ${message}`);
  process.exit(1);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

function readText(filePath) {
  assert(fs.existsSync(filePath), `missing required file: ${filePath}`);
  return fs.readFileSync(filePath, 'utf8');
}

function readRustTree(entryPath) {
  if (!fs.existsSync(entryPath)) {
    return '';
  }

  const stats = fs.statSync(entryPath);
  if (stats.isDirectory()) {
    return fs
      .readdirSync(entryPath, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))
      .map((entry) => readRustTree(path.join(entryPath, entry.name)))
      .filter(Boolean)
      .join('\n');
  }

  return entryPath.endsWith('.rs') ? readText(entryPath) : '';
}

function readTypeScriptTree(entryPath) {
  if (!fs.existsSync(entryPath)) {
    return '';
  }

  const stats = fs.statSync(entryPath);
  if (stats.isDirectory()) {
    return fs
      .readdirSync(entryPath, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))
      .map((entry) => readTypeScriptTree(path.join(entryPath, entry.name)))
      .filter(Boolean)
      .join('\n');
  }

  return /\.(ts|tsx)$/.test(entryPath) ? readText(entryPath) : '';
}

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');
const commandsPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands.rs');
const sharedCommandsPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands', 'shared', 'mod.rs');
const sharedCommandsDirPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands', 'shared');
const syncRuntimePath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands', 'sync', 'runtime.rs');
const syncRuntimeDirPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands', 'sync', 'runtime');
const syncStatusSchemaPath = path.join(repoRoot, 'lorvex-store', 'src', 'sync_status');
const syncFilesystemBridgePath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands', 'sync', 'filesystem_bridge.rs');
const syncFilesystemBridgeDirPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands', 'sync', 'filesystem_bridge');
const legacyIpcPath = path.join(repoRoot, 'app', 'src', 'lib', 'ipc.ts');
const ipcDirPath = path.join(repoRoot, 'app', 'src', 'lib', 'ipc');
const syncSettingsPanelPath = path.join(
  repoRoot,
  'app',
  'src',
  'components',
  'settings',
  'assistant',
  'sync-settings',
);
const syncSettingsBackendContextPath = path.join(
  repoRoot,
  'app',
  'src',
  'components',
  'settings',
  'assistant',
  'sync-settings',
  'backendContext.ts',
);
// The MCP server's sync surface now lives under `mcp-server/src/system/sync/`.
// This verifier scans that tree rather than pinning a single file path, so
// future relocations within `mcp-server/src/` continue to pick up the relevant
// Rust source automatically.
const mcpServerSyncRustDirPath = path.join(repoRoot, 'mcp-server', 'src', 'system', 'sync');

const commandsRootSource = readText(commandsPath);
const sharedCommandsSource = [readText(sharedCommandsPath), readRustTree(sharedCommandsDirPath)].join('\n');
const syncRuntimeSource = [readText(syncRuntimePath), readRustTree(syncRuntimeDirPath)].join('\n');
const syncStatusSchemaSource = readRustTree(syncStatusSchemaPath);
assert(syncStatusSchemaSource.length > 0, `missing required Rust tree: ${syncStatusSchemaPath}`);
const syncFilesystemBridgeSource = [readText(syncFilesystemBridgePath), readRustTree(syncFilesystemBridgeDirPath)].join('\n');
const commandsSource = `${commandsRootSource}\n${sharedCommandsSource}\n${syncRuntimeSource}\n${syncFilesystemBridgeSource}\n${syncStatusSchemaSource}`;
const ipcSource = [
  fs.existsSync(legacyIpcPath) ? readText(legacyIpcPath) : '',
  readTypeScriptTree(ipcDirPath),
].join('\n');
assert(ipcSource.trim().length > 0, `missing required TypeScript IPC tree: ${ipcDirPath}`);
const syncSettingsPanelSource = readTypeScriptTree(syncSettingsPanelPath);
const syncSettingsBackendContextSource = readText(syncSettingsBackendContextPath);
const strictLocaleCatalogs = readStrictParityLocaleCodes(repoRoot).map((localeCode) => [
  localeCode,
  readLocaleCatalog(repoRoot, localeCode),
]);
const mcpServerSyncRustSource = [
  readRustTree(mcpServerSyncRustDirPath),
  syncStatusSchemaSource,
].join('\n');
assert(
  mcpServerSyncRustSource.length > 0,
  `missing required Rust tree: ${mcpServerSyncRustDirPath}`,
);

assert(
  /const\s+SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY\s*:\s*&str\s*=/.test(commandsSource),
  'commands module tree must define SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY',
);
assert(
  /struct\s+FilesystemBridgePullCursor\s*\{[\s\S]*updated_at\s*:\s*String,[\s\S]*device_id\s*:\s*String,[\s\S]*event_id\s*:\s*String/.test(
    syncFilesystemBridgeSource,
  ),
  'sync_filesystem_bridge module tree must define FilesystemBridgePullCursor with updated_at/device_id/event_id',
);
assert(
  /fn\s+load_filesystem_bridge_pull_cursor\s*\(/.test(syncFilesystemBridgeSource),
  'sync_filesystem_bridge module tree must implement load_filesystem_bridge_pull_cursor()',
);
assert(
  /fn\s+store_filesystem_bridge_pull_cursor\s*\(/.test(syncFilesystemBridgeSource),
  'sync_filesystem_bridge module tree must implement store_filesystem_bridge_pull_cursor()',
);
assert(
  /fn\s+newest_filesystem_bridge_pull_cursor\s*\(/.test(syncFilesystemBridgeSource),
  'sync_filesystem_bridge module tree must implement newest_filesystem_bridge_pull_cursor()',
);
assert(
  /pub\s+struct\s+SyncStatusSnapshot\s*\{[\s\S]*filesystem_bridge_last_pull_cursor\s*:\s*Option<String>,[\s\S]*filesystem_bridge_last_pull_updated_at\s*:\s*Option<String>,[\s\S]*filesystem_bridge_last_pull_device_id\s*:\s*Option<String>,[\s\S]*filesystem_bridge_last_pull_event_id\s*:\s*Option<String>,[\s\S]*filesystem_bridge_last_pull_cursor_malformed\s*:\s*bool/.test(
    commandsSource,
  ),
  'SyncStatus must expose raw/parsed filesystem-bridge cursor fields and malformed flag in Rust',
);
assert(
  /pub type SyncStatus = lorvex_store::SyncStatusSnapshot/.test(commandsSource),
  'app SyncStatus must alias the shared store snapshot schema',
);
assert(
  /sync_backend_kind_malformed_reason\s*:\s*Option<String>/.test(commandsSource),
  'SyncStatus must expose sync_backend_kind_malformed_reason in Rust',
);
assert(
  /filesystem_bridge_lookback_known_id_skipped_last_run\s*:\s*i64/.test(commandsSource),
  'SyncStatus must expose filesystem_bridge_lookback_known_id_skipped_last_run in Rust',
);
assert(
  /filesystem_bridge_lookback_known_id_skipped_last_run_malformed\s*:\s*bool/.test(commandsSource),
  'SyncStatus must expose filesystem_bridge_lookback_known_id_skipped_last_run_malformed in Rust',
);
assert(
  /filesystem_bridge_lookback_known_id_skipped_last_run_at\s*:\s*Option<String>/.test(commandsSource),
  'SyncStatus must expose filesystem_bridge_lookback_known_id_skipped_last_run_at in Rust',
);
assert(
  /filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed\s*:\s*bool/.test(commandsSource),
  'SyncStatus must expose filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed in Rust',
);
assert(
  /last_synced_at_malformed\s*:\s*bool/.test(commandsSource),
  'SyncStatus must expose last_synced_at_malformed in Rust',
);
assert(
  /last_success_at_malformed\s*:\s*bool/.test(commandsSource),
  'SyncStatus must expose last_success_at_malformed in Rust',
);
assert(
  /last_pull_at_malformed\s*:\s*bool/.test(commandsSource),
  'SyncStatus must expose last_pull_at_malformed in Rust',
);
assert(
  /export\s+interface\s+SyncStatus\s*\{[\s\S]*filesystem_bridge_last_pull_cursor:\s*string\s*\|\s*null;[\s\S]*filesystem_bridge_last_pull_updated_at:\s*string\s*\|\s*null;[\s\S]*filesystem_bridge_last_pull_device_id:\s*string\s*\|\s*null;[\s\S]*filesystem_bridge_last_pull_event_id:\s*string\s*\|\s*null;[\s\S]*filesystem_bridge_last_pull_cursor_malformed:\s*boolean;/.test(
    ipcSource,
  ),
  'SyncStatus must expose raw/parsed filesystem-bridge cursor fields and malformed flag in TS IPC contract',
);
assert(
  /sync_backend_kind_malformed_reason:\s*string\s*\|\s*null;/.test(ipcSource),
  'SyncStatus must expose sync_backend_kind_malformed_reason in TS IPC contract',
);
assert(
  /filesystem_bridge_lookback_known_id_skipped_last_run:\s*number;/.test(ipcSource),
  'SyncStatus must expose filesystem_bridge_lookback_known_id_skipped_last_run in TS IPC contract',
);
assert(
  /filesystem_bridge_lookback_known_id_skipped_last_run_malformed:\s*boolean;/.test(ipcSource),
  'SyncStatus must expose filesystem_bridge_lookback_known_id_skipped_last_run_malformed in TS IPC contract',
);
assert(
  /filesystem_bridge_lookback_known_id_skipped_last_run_at:\s*string\s*\|\s*null;/.test(ipcSource),
  'SyncStatus must expose filesystem_bridge_lookback_known_id_skipped_last_run_at in TS IPC contract',
);
assert(
  /filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed:\s*boolean;/.test(ipcSource),
  'SyncStatus must expose filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed in TS IPC contract',
);
assert(
  /last_synced_at_malformed:\s*boolean;/.test(ipcSource),
  'SyncStatus must expose last_synced_at_malformed in TS IPC contract',
);
assert(
  /last_success_at_malformed:\s*boolean;/.test(ipcSource),
  'SyncStatus must expose last_success_at_malformed in TS IPC contract',
);
assert(
  /last_pull_at_malformed:\s*boolean;/.test(ipcSource),
  'SyncStatus must expose last_pull_at_malformed in TS IPC contract',
);
// The sync-settings subtree was refactored from inline `<Field
// label={t('settings.X')}>` props into a config-array shape where each
// row is described by a `malformedKey: 'settings.X'` (or `key:`) entry
// and a separate `syncStatus.<field>` reference. The structural intent
// is unchanged: every key below must appear somewhere in the subtree
// alongside its corresponding `syncStatus.<field>` reference. We
// assert presence in the concatenated subtree source rather than
// pinning a specific JSX shape.
function assertPanelRowExists(i18nKey, statusField, label) {
  assert(
    syncSettingsPanelSource.includes(`'${i18nKey}'`)
      && syncSettingsPanelSource.includes(`syncStatus.${statusField}`),
    `sync-settings subtree must surface ${label} (${i18nKey} + syncStatus.${statusField})`,
  );
}
assertPanelRowExists('settings.syncLastSyncedMalformed', 'last_synced_at_malformed', 'malformed diagnostics for last_synced_at');
assertPanelRowExists('settings.syncLastSuccessMalformed', 'last_success_at_malformed', 'malformed diagnostics for last_success_at');
assertPanelRowExists('settings.syncLastPullMalformed', 'last_pull_at_malformed', 'malformed diagnostics for last_pull_at');
assertPanelRowExists(
  'settings.syncFilesystemBridgeCursorMalformed',
  'filesystem_bridge_last_pull_cursor_malformed',
  'filesystem-bridge cursor malformed diagnostics row',
);
assert(
  syncSettingsPanelSource.includes('filesystem_bridge_last_pull_cursor_malformed_reason'),
  'sync-settings subtree must reference filesystem_bridge_last_pull_cursor_malformed_reason',
);
assertPanelRowExists(
  'settings.syncFilesystemBridgeCursorUpdatedAt',
  'filesystem_bridge_last_pull_updated_at',
  'filesystem-bridge cursor updated_at diagnostics row',
);
assertPanelRowExists(
  'settings.syncFilesystemBridgeCursorDeviceId',
  'filesystem_bridge_last_pull_device_id',
  'filesystem-bridge cursor device_id diagnostics row',
);
assertPanelRowExists(
  'settings.syncFilesystemBridgeCursorEventId',
  'filesystem_bridge_last_pull_event_id',
  'filesystem-bridge cursor event_id diagnostics row',
);
assertPanelRowExists(
  'settings.syncFilesystemBridgeLookbackKnownIdSkippedLastRun',
  'filesystem_bridge_lookback_known_id_skipped_last_run',
  'filesystem-bridge lookback known-id skip metric',
);
assertPanelRowExists(
  'settings.syncFilesystemBridgeLookbackKnownIdSkippedMalformed',
  'filesystem_bridge_lookback_known_id_skipped_last_run_malformed',
  'malformed diagnostics for filesystem-bridge lookback known-id skip metric',
);
assertPanelRowExists(
  'settings.syncFilesystemBridgeLookbackKnownIdSkippedAt',
  'filesystem_bridge_lookback_known_id_skipped_last_run_at',
  'timestamp diagnostics for filesystem-bridge lookback known-id skip metric',
);
assertPanelRowExists(
  'settings.syncFilesystemBridgeLookbackKnownIdSkippedAtMalformed',
  'filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed',
  'malformed diagnostics for filesystem-bridge lookback known-id skip timestamp',
);
assert(
  /shouldShowRuntimeBackendDiagnostics\(\s*syncStatus,\s*SYNC_BACKEND_FILESYSTEM_BRIDGE\s*\)/.test(
    syncSettingsPanelSource,
  ) && /sync_backend_kind_effective === backendKind/.test(syncSettingsBackendContextSource),
  'SyncSettingsPanel must gate filesystem-bridge cursor diagnostics through the shared runtime backend context helper',
);
const filesystemBridgeCursorDiagnosticLocaleKeys = [
  'settings.syncFilesystemBridgeCursorMalformed',
  'settings.syncLastSyncedMalformed',
  'settings.syncLastSuccessMalformed',
  'settings.syncLastPullMalformed',
  'settings.syncFilesystemBridgeCursorUpdatedAt',
  'settings.syncFilesystemBridgeCursorDeviceId',
  'settings.syncFilesystemBridgeCursorEventId',
  'settings.syncFilesystemBridgeLookbackKnownIdSkippedLastRun',
  'settings.syncFilesystemBridgeLookbackKnownIdSkippedMalformed',
  'settings.syncFilesystemBridgeLookbackKnownIdSkippedAt',
  'settings.syncFilesystemBridgeLookbackKnownIdSkippedAtMalformed',
];
for (const [localeCode, catalog] of strictLocaleCatalogs) {
  const missing = missingLocaleCatalogKeys(catalog, filesystemBridgeCursorDiagnosticLocaleKeys);
  assert(
    missing.length === 0,
    `${localeCode} strict-parity locale must define filesystem-bridge cursor diagnostics labels: missing ${
      missing.join(', ')
    }`,
  );
}
assert(
  /lorvex_store::load_sync_status_snapshot\(conn\)[\s\S]*serde_json::to_string_pretty\(&snapshot\)/.test(
    mcpServerSyncRustSource,
  ) &&
    /SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY/.test(mcpServerSyncRustSource) &&
    /last_synced_at_malformed\s*:\s*bool/.test(mcpServerSyncRustSource) &&
    /last_success_at_malformed\s*:\s*bool/.test(mcpServerSyncRustSource) &&
    /last_pull_at_malformed\s*:\s*bool/.test(mcpServerSyncRustSource) &&
    /sync_backend_kind\s*:\s*Option<String>/.test(mcpServerSyncRustSource) &&
    /filesystem_bridge_last_pull_cursor\s*:\s*Option<String>/.test(mcpServerSyncRustSource) &&
    /filesystem_bridge_last_pull_updated_at\s*:\s*Option<String>/.test(mcpServerSyncRustSource) &&
    /filesystem_bridge_last_pull_device_id\s*:\s*Option<String>/.test(mcpServerSyncRustSource) &&
    /filesystem_bridge_last_pull_event_id\s*:\s*Option<String>/.test(mcpServerSyncRustSource) &&
    /filesystem_bridge_last_pull_cursor_malformed\s*:\s*bool/.test(mcpServerSyncRustSource) &&
    /filesystem_bridge_lookback_known_id_skipped_last_run\s*:\s*i64/.test(mcpServerSyncRustSource) &&
    /filesystem_bridge_lookback_known_id_skipped_last_run_malformed\s*:\s*bool/.test(mcpServerSyncRustSource) &&
    /filesystem_bridge_lookback_known_id_skipped_last_run_at\s*:\s*Option<String>/.test(mcpServerSyncRustSource) &&
    /filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed\s*:\s*bool/.test(mcpServerSyncRustSource),
  'mcp-server get_sync_status must expose sync_backend_kind and filesystem-bridge cursor diagnostics fields',
);
assert(
  /fn\s+collect_remote_filesystem_bridge_envelopes\s*\([\s\S]*since:\s*Option<&FilesystemBridgePullCursor>/.test(
    syncFilesystemBridgeSource,
  ),
  'collect_remote_filesystem_bridge_envelopes() must accept filesystem-bridge cursor checkpoint input',
);
assert(
  /struct\s+CollectedRemoteFilesystemBridgeEnvelopes\s*\{[\s\S]*lookback_known_id_skipped\s*:\s*i64/.test(
    syncFilesystemBridgeSource,
  ),
  'CollectedRemoteFilesystemBridgeEnvelopes must expose lookback_known_id_skipped accounting',
);
assert(
  /pub\s+struct\s+FilesystemBridgeSyncResult\s*\{[\s\S]*lookback_known_id_skipped\s*:\s*i64/.test(
    commandsSource,
  ),
  'FilesystemBridgeSyncResult must expose lookback_known_id_skipped in Rust',
);
assert(
  /export\s+interface\s+FilesystemBridgeSyncResult\s*\{[\s\S]*lookback_known_id_skipped:\s*number;/.test(
    ipcSource,
  ),
  'FilesystemBridgeSyncResult must expose lookback_known_id_skipped in TS IPC contract',
);
assert(
  /label=\{t\('settings\.syncSummaryLookbackKnownIdSkipped'\)\}/.test(
    syncSettingsPanelSource,
  ) && /lastSyncRunResult\.backendResult\.lookback_known_id_skipped/.test(syncSettingsPanelSource),
  'sync settings subtree must surface lookback-known-id skip metric in the manual sync summary',
);
for (const [localeCode, catalog] of strictLocaleCatalogs) {
  assert(
    missingLocaleCatalogKeys(catalog, ['settings.syncSummaryLookbackKnownIdSkipped']).length === 0,
    `${localeCode} strict-parity locale must define syncSummaryLookbackKnownIdSkipped`,
  );
}
assert(
  /fn\s+phase_read_outbox_and_pull_state\s*\([\s\S]*let\s+last_pull_cursor\s*=\s*load_filesystem_bridge_pull_cursor\(conn\)\?;[\s\S]*SyncReadState\s*\{[\s\S]*last_pull_cursor,[\s\S]*\}/.test(
    syncFilesystemBridgeSource,
  ),
  'filesystem bridge Phase A read state must load filesystem-bridge pull cursor before later collection phases consume it',
);
assert(
  /collect_remote_filesystem_bridge_envelopes\([\s\S]*last_pull_cursor\.as_ref\(\)/.test(syncFilesystemBridgeSource),
  'filesystem bridge runtime must pass filesystem-bridge cursor into collection phase',
);
const newestCursorFromCollectedEventsRe =
  /let\s+newest_pull_cursor\s*=\s*if\s+collected_remote\.cursor_blocking_parse_errors\s*==\s*0\s*\{[\s\S]*?newest_filesystem_bridge_pull_cursor\(&collected_remote\.remote_events\)[\s\S]*?\}\s*else\s*\{[\s\S]*?None[\s\S]*?\}\s*;/;
assert(
  /cursor_blocking_parse_errors\s*:\s*i64/.test(syncFilesystemBridgeSource)
    && newestCursorFromCollectedEventsRe.test(syncFilesystemBridgeSource),
  'filesystem bridge runtime must derive newest filesystem-bridge cursor from collected events only when cursor-blocking parse errors are absent',
);
assert(
  /fn\s+apply_remote_sync_envelopes_with_filesystem_bridge_cursor\s*\([\s\S]*filesystem_bridge_cursor:\s*Option<&FilesystemBridgePullCursor>/.test(
    commandsSource,
  ),
  'commands.rs must expose transactional apply helper with optional filesystem-bridge cursor',
);
assert(
  /apply_remote_sync_envelopes_with_filesystem_bridge_cursor[\s\S]*store_filesystem_bridge_pull_cursor\(conn,\s*cursor\)\?;/.test(
    commandsSource,
  ),
  'transactional apply helper must persist filesystem-bridge cursor checkpoint',
);
// The orchestrator's terminal expression was extracted into a
// `build_filesystem_bridge_sync_result` builder once the function grew
// past ~150 lines, so the regex now matches either the inline struct
// literal or the builder call. Both shapes satisfy the structural
// intent (the function returns `FilesystemBridgeSyncResult` after the
// pull/apply phases).
const runLocalMatch = syncFilesystemBridgeSource.match(
  /fn\s+run_filesystem_bridge_sync_inner\s*\([\s\S]*?Ok\((?:FilesystemBridgeSyncResult|build_filesystem_bridge_sync_result)[\s\S]*?\n}\n/,
);
assert(runLocalMatch, 'sync_filesystem_bridge module tree must define run_filesystem_bridge_sync_inner()');
const runLocalSource = runLocalMatch[0];
assert(
  new RegExp(
    String.raw`fn\s+phase_apply_and_finalize\s*\([\s\S]*${newestCursorFromCollectedEventsRe.source}[\s\S]*apply_incoming_via_envelope\([\s\S]*newest_pull_cursor\.as_ref\(\)`,
  ).test(
    syncFilesystemBridgeSource,
  ),
  'filesystem bridge finalize phase must route apply + cursor persistence through the shared envelope apply wrapper',
);
assert(
  !/store_filesystem_bridge_pull_cursor\(/.test(runLocalSource),
  'run_filesystem_bridge_sync_inner() must not persist cursor outside transactional apply helper',
);
assert(
  /fn\s+apply_incoming_via_envelope\s*\([\s\S]*filesystem_bridge_cursor:\s*Option<&(?:super::cursor::)?FilesystemBridgePullCursor>[\s\S]*apply_remote_sync_records_with_checkpoint_writer\(/.test(
    syncFilesystemBridgeSource,
  ),
  'filesystem bridge runtime wrapper must delegate cursor-aware apply through the shared remote-apply coordinator',
);

console.log('[verify:sync-filesystem-bridge-cursor-contract] Filesystem-bridge cursor contract checks passed.');
