#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { readSourceTree, stripSourceComments } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:sync-backend-profile-contract]';

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

function resolveSourceEntry(...candidates) {
  const match = candidates.find((candidate) => fs.existsSync(candidate));
  if (!match) {
    fail(`Missing required file: ${candidates[0]}`);
  }
  return match;
}

function fail(message) {
  throw new Error(`${SCRIPT_TAG} ${message}`);
}

function assertMatch(source, pattern, message) {
  if (!pattern.test(source)) {
    fail(message);
  }
}

function assertNoMatch(source, pattern, message) {
  if (pattern.test(source)) {
    fail(message);
  }
}

export function verifySyncBackendProfileContract({ repoRoot = resolveRepoRoot() } = {}) {
  const syncBackendSource = stripSourceComments(readSourceTree(resolveSourceEntry(
    path.join(repoRoot, 'app', 'src', 'lib', 'syncBackend'),
    path.join(repoRoot, 'app', 'src', 'lib', 'syncBackend.ts'),
  )));
  const settingsSource = stripSourceComments(fs.readFileSync(
    path.join(repoRoot, 'app', 'src', 'components', 'SettingsView.tsx'),
    'utf8',
  ));
  const assistantControllerRootSource = stripSourceComments(fs.readFileSync(
    path.join(repoRoot, 'app', 'src', 'components', 'settings', 'controller', 'useAssistantSettingsController.ts'),
    'utf8',
  ));
  const assistantSyncSource = stripSourceComments(readSourceTree(resolveSourceEntry(
    path.join(repoRoot, 'app', 'src', 'components', 'settings', 'controller', 'assistant', 'sync.ts'),
    path.join(repoRoot, 'app', 'src', 'components', 'settings', 'controller', 'assistant', 'sync'),
  )));
  const syncSettingsPanelSource = stripSourceComments(fs.readFileSync(
    path.join(repoRoot, 'app', 'src', 'components', 'settings', 'assistant', 'sync-settings', 'SyncSettingsPanel.tsx'),
    'utf8',
  ));
  const syncSettingsSubtreeSource = stripSourceComments(readSourceTree(resolveSourceEntry(
    path.join(repoRoot, 'app', 'src', 'components', 'settings', 'assistant', 'sync-settings'),
    path.join(repoRoot, 'app', 'src', 'components', 'settings', 'assistant', 'sync-settings', 'SyncSettingsPanel.tsx'),
  )));

  assertMatch(syncBackendSource, /export const SYNC_BACKEND_FILESYSTEM_BRIDGE\b/, 'syncBackend should export SYNC_BACKEND_FILESYSTEM_BRIDGE');
  assertNoMatch(syncBackendSource, /cloudkit_private|SYNC_BACKEND_CLOUDKIT_PRIVATE/, 'syncBackend must not expose retired CloudKit backend names');
  assertMatch(syncBackendSource, /export function getDefaultSyncBackendKind\(/, 'syncBackend should export getDefaultSyncBackendKind()');
  assertMatch(syncBackendSource, /export function listAvailableSyncBackends\(/, 'syncBackend should export listAvailableSyncBackends()');
  assertMatch(syncBackendSource, /export function resolveSyncBackend\(/, 'syncBackend should export resolveSyncBackend()');
  assertMatch(syncBackendSource, /export function buildSyncBackendConfig\(/, 'syncBackend should export buildSyncBackendConfig()');
  assertMatch(syncBackendSource, /availableBackendKinds/, 'syncBackend support context should use availableBackendKinds');
  assertMatch(syncBackendSource, /supportedSyncBackendKinds/, 'sync backend support should derive from RuntimeProfile.supportedSyncBackendKinds');
  assertMatch(syncBackendSource, /includes\(/, 'sync backend availability should be derived from backend kind membership checks');

  assertMatch(settingsSource, /useAssistantSettingsController\(\{/, 'SettingsView should delegate assistant sync orchestration through useAssistantSettingsController()');
  assertMatch(
    assistantControllerRootSource,
    /import \{ useAssistantSyncController \} from '\.\/assistant\/sync';/,
    'assistant settings controller root should delegate sync orchestration to assistant/sync',
  );
  assertMatch(assistantSyncSource, /listAvailableSyncBackends\(/, 'assistant sync subtree should derive selectable backends from listAvailableSyncBackends()');
  assertMatch(
    assistantSyncSource,
    /resolveStoredSyncBackendSettings\(/,
    'assistant sync subtree should normalize persisted backend state through resolveStoredSyncBackendSettings()',
  );
  assertMatch(assistantSyncSource, /buildSyncBackendConfig\(/, 'assistant sync subtree should build backend-specific configs through buildSyncBackendConfig()');

  assertMatch(syncSettingsPanelSource, /sync: AssistantSyncSettingsModel;/, 'SyncSettingsPanel props should accept AssistantSyncSettingsModel');
  assertMatch(syncBackendSource, /export interface SyncBackendDescriptor\b/, 'syncBackend should export SyncBackendDescriptor');
  assertMatch(
    syncSettingsSubtreeSource,
    /availableSyncBackendDescriptors\.map\(/,
    'sync settings subtree should render backend choices from availableSyncBackendDescriptors',
  );

  return { ok: true };
}

function runCli() {
  try {
    verifySyncBackendProfileContract();
    console.log(`${SCRIPT_TAG} Sync backend profile contract checks passed.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
