#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { readSourceTree, stripSourceComments } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:sync-backend-abstraction-contract]';

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

export function verifySyncBackendAbstractionContract({ repoRoot = resolveRepoRoot() } = {}) {
  const syncBackendSource = stripSourceComments(readSourceTree(resolveSourceEntry(
    path.join(repoRoot, 'app', 'src', 'lib', 'syncBackend'),
    path.join(repoRoot, 'app', 'src', 'lib', 'syncBackend.ts'),
  )));
  const syncPreferencesPath = path.join(repoRoot, 'app', 'src', 'lib', 'sync', 'preferences.ts');
  const syncRuntimePath = path.join(repoRoot, 'app', 'src', 'lib', 'sync', 'runtime.ts');
  const syncPreferencesSource = stripSourceComments(readSourceTree(
    fs.existsSync(syncPreferencesPath)
      ? syncPreferencesPath
      : path.join(repoRoot, 'app', 'src', 'lib', 'sync.ts'),
  ));
  const syncRuntimeSource = stripSourceComments(readSourceTree(
    fs.existsSync(syncRuntimePath)
      ? syncRuntimePath
      : path.join(repoRoot, 'app', 'src', 'lib', 'sync.ts'),
  ));
  const syncFacadeSource = stripSourceComments(readSourceTree(resolveSourceEntry(
    path.join(repoRoot, 'app', 'src', 'lib', 'sync.ts'),
    path.join(repoRoot, 'app', 'src', 'lib', 'sync'),
  )));

  assertMatch(syncBackendSource, /export type SyncBackendKind\b/, 'syncBackend should export SyncBackendKind');
  assertMatch(syncBackendSource, /export (?:type|interface) SyncBackendConfig\b/, 'syncBackend should export SyncBackendConfig');
  assertMatch(syncBackendSource, /export interface ResolvedSyncBackend\b/, 'syncBackend should export ResolvedSyncBackend');
  assertMatch(syncBackendSource, /export function resolveSyncBackend\(/, 'syncBackend should export resolveSyncBackend()');
  assertMatch(syncBackendSource, /export function buildSyncBackendConfig\(/, 'syncBackend should export buildSyncBackendConfig()');
  assertMatch(syncBackendSource, /export async function runSyncBackend\(/, 'syncBackend should export runSyncBackend()');
  assertMatch(
    syncBackendSource,
    /while\s*\(\s*result\.pull_limit_hit[\s\S]*consecutiveRepulls < options\.maxConsecutiveRepulls[\s\S]*!options\.isCancelled\(\)\s*\)/,
    'syncBackend runtime should support bounded filesystem-bridge repulls while pull_limit_hit is true',
  );
  assertMatch(
    syncBackendSource,
    /quickRetryRequested:\s*filesystemBridgeResult\?\.pull_limit_hit \?\? false/,
    'syncBackend runtime should propagate filesystem-bridge pull_limit_hit into quickRetryRequested',
  );
  assertMatch(
    syncBackendSource,
    /pullLimitHit:\s*result\.filesystemBridgeResult\.pull_limit_hit/,
    'syncBackend summary should surface filesystem-bridge pull_limit_hit',
  );

  assertMatch(
    syncPreferencesSource,
    /resolveStoredSyncBackendSettings\(\{|resolveSyncBackend\(/,
    'sync orchestration should resolve backend selection through resolveSyncBackend() or resolveStoredSyncBackendSettings()',
  );
  assertMatch(
    syncPreferencesSource,
    /buildSyncBackendConfig\(\{/,
    'sync orchestration should build backend configs through the shared backend helper',
  );
  assertMatch(
    syncRuntimeSource,
    /runSyncBackend\(\{/,
    'sync runtime should call runSyncBackend() rather than branch per backend inline',
  );
  assertNoMatch(
    syncRuntimeSource,
    /remote_provider'\s*\)|===\s*['"]remote_provider['"]|runRemoteProviderSync\(|runFilesystemBridgeSync\(/,
    'sync runtime should not keep inline backend-specific execution branches',
  );
  if (fs.existsSync(syncRuntimePath)) {
    const legacySyncFacadePath = path.join(repoRoot, 'app', 'src', 'lib', 'sync.ts');
    if (fs.existsSync(legacySyncFacadePath)) {
      // Legacy single-file shape still on disk: keep enforcing the
      // facade re-export so the file does not silently drift back
      // into duplicating runtime logic.
      assertMatch(
        syncFacadeSource,
        /export \{ useBackgroundSyncBackend \} from '\.\/sync\/runtime';/,
        'sync.ts should remain a thin facade over sync/runtime once the sync subtree exists',
      );
    } else {
      // Post-decomposition the legacy `sync.ts` façade was removed
      // entirely; consumers import `useBackgroundSyncBackend` directly
      // from `./sync/runtime`. Anchor the structural intent (the hook
      // is exported from the runtime module) at the source-of-truth
      // declaration site.
      assertMatch(
        syncRuntimeSource,
        /export function useBackgroundSyncBackend\(/,
        'sync/runtime.ts must export useBackgroundSyncBackend()',
      );
    }
  }

  return { ok: true };
}

function runCli() {
  try {
    verifySyncBackendAbstractionContract();
    console.log(`${SCRIPT_TAG} Sync backend abstraction checks passed.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
