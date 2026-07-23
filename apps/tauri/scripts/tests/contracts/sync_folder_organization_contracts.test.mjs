import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('sync runtime is organized as a folder-backed subsystem with cadence, network, preferences, runtime, and runtime logic modules', () => {
  const appShellSource = fs.readFileSync(path.join(repoRoot, 'app/src/app-shell/MainWindowApp.tsx'), 'utf8');
  const cadenceSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/sync/cadence.ts'), 'utf8');
  const networkSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/sync/network.ts'), 'utf8');
  const preferencesSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/sync/preferences.ts'), 'utf8');
  const runtimeLogicSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/sync/runtime.logic.ts'), 'utf8');
  const runtimeSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/sync/runtime.ts'), 'utf8');

  assert.match(appShellSource, /useBackgroundSyncBackend\(runtimeProfile\.supportsBackgroundSync\);/);

  assert.match(cadenceSource, /const SYNC_LOOP_DESKTOP_MS = 60_000;/);
  assert.match(cadenceSource, /export function computeSyncCadenceDelay\(/);
  assert.match(cadenceSource, /export function shouldForceAndroidResumeResync\(/);

  assert.match(networkSource, /export function getNavigatorConnection\(\): NavigatorConnectionLike \| null \{/);
  assert.match(networkSource, /export function readNetworkCadenceHints\(\): NetworkCadenceHints \{/);

  assert.match(preferencesSource, /export async function loadResolvedBackgroundSyncPreferences\(/);
  assert.match(preferencesSource, /export function scheduleResolvedBackgroundSyncNormalization\(/);
  assert.match(preferencesSource, /resolveStoredSyncBackendSettings\(/);
  assert.match(preferencesSource, /buildSyncBackendConfig\(/);
  assert.doesNotMatch(
    preferencesSource,
    /useEffect|useRef|window\.addEventListener|document\.addEventListener/,
    'sync preference support should not own React runtime or browser event wiring',
  );

  assert.match(runtimeLogicSource, /export function createBackgroundSyncRuntimeController\(/);
  assert.doesNotMatch(
    runtimeLogicSource,
    /useEffect|useRef|window\.addEventListener|document\.addEventListener/,
    'background sync runtime logic should stay detached from React lifecycle and browser event wiring',
  );

  assert.match(runtimeSource, /export function useBackgroundSyncBackend\(enabled = true\): void \{/);
  assert.match(runtimeSource, /from '\.\/cadence';/);
  assert.match(runtimeSource, /from '\.\/network';/);
  assert.match(runtimeSource, /from '\.\/preferences';/);
  assert.match(runtimeSource, /from '\.\/runtime\.logic';/);
});
