#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { readSourceTree, stripSourceComments } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:sync-backend-manual-runner-contract]';

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

export function verifySyncBackendManualRunnerContract({ repoRoot = resolveRepoRoot() } = {}) {
  const syncBackendSource = stripSourceComments(readSourceTree(resolveSourceEntry(
    path.join(repoRoot, 'app', 'src', 'lib', 'syncBackend'),
    path.join(repoRoot, 'app', 'src', 'lib', 'syncBackend.ts'),
  )));
  const settingsSource = stripSourceComments(fs.readFileSync(
    path.join(repoRoot, 'app', 'src', 'components', 'SettingsView.tsx'),
    'utf8',
  ));
  const assistantSyncSource = stripSourceComments(readSourceTree(resolveSourceEntry(
    path.join(repoRoot, 'app', 'src', 'components', 'settings', 'controller', 'assistant', 'sync.ts'),
    path.join(repoRoot, 'app', 'src', 'components', 'settings', 'controller', 'assistant', 'sync'),
  )));

  assertMatch(syncBackendSource, /export interface RunSyncBackendNowOptions\b/, 'syncBackend should export RunSyncBackendNowOptions');
  assertMatch(syncBackendSource, /export type RunSyncBackendNowResult\b|export interface RunSyncBackendNowResult\b/, 'syncBackend should export RunSyncBackendNowResult');
  assertMatch(syncBackendSource, /export async function runSyncBackendNow\(/, 'syncBackend should export runSyncBackendNow()');
  assertMatch(syncBackendSource, /backend:\s*SyncBackendConfig/, 'manual sync runner should center on a backend config object');

  assertMatch(settingsSource, /useAssistantSettingsController\(\{/, 'SettingsView should delegate assistant sync orchestration through useAssistantSettingsController()');
  assertMatch(assistantSyncSource, /runSyncBackendNow\(/, 'assistant sync subtree should delegate manual sync execution to runSyncBackendNow()');
  assertNoMatch(assistantSyncSource, /runRemoteProviderSync\(/, 'assistant sync subtree must not call runRemoteProviderSync() directly in manual sync flow');
  assertNoMatch(assistantSyncSource, /runFilesystemBridgeSync\(/, 'assistant sync subtree must not call runFilesystemBridgeSync() directly in manual sync flow');

  return { ok: true };
}

function runCli() {
  try {
    verifySyncBackendManualRunnerContract();
    console.log(`${SCRIPT_TAG} Manual runner contract checks passed.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
