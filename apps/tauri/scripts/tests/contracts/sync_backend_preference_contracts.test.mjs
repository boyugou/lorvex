import assert from 'node:assert/strict';
import test from 'node:test';

import { readTypeScriptSources } from './shared.mjs';

test('sync backend preference parsing and normalization stay shared between Settings and background sync', () => {
  const syncBackendSource = readTypeScriptSources(
    'app/src/lib/syncBackend/runtime.ts',
    'app/src/lib/syncBackend',
  );
  const syncPreferencesSource = readTypeScriptSources('app/src/lib/sync/preferences.ts');
  const assistantSyncSource = readTypeScriptSources('app/src/components/settings/controller/assistant/sync');

  assert.match(
    syncBackendSource,
    /export function parseStoredSyncEnabledPreference\(/,
    'syncBackend subtree should expose a shared persisted sync-enabled parser',
  );
  assert.match(
    syncBackendSource,
    /export function parseStoredSyncBackendKindPreference\(/,
    'syncBackend subtree should expose a shared persisted sync-backend-kind parser',
  );
  assert.match(
    syncBackendSource,
    /export function parseStoredSyncBackendKindPreferenceState\(/,
    'syncBackend subtree should expose a shared persisted sync-backend-kind state parser',
  );
  assert.match(
    syncBackendSource,
    /export function resolveStoredSyncBackendSettings\(/,
    'syncBackend subtree should expose a shared persisted sync-backend resolver',
  );
  assert.match(
    syncPreferencesSource,
    /resolveStoredSyncBackendSettings\(\{\s*enabledRaw,\s*backendKindRaw,\s*backendConfigsRaw,/,
    'background sync should resolve persisted sync backend settings through the shared helper',
  );
  assert.match(
    assistantSyncSource,
    /resolveStoredSyncBackendSettings\(\{\s*enabledRaw,\s*backendKindRaw,\s*backendConfigsRaw,/,
    'assistant settings sync subtree should resolve persisted sync backend settings through the shared helper',
  );
  assert.match(
    syncPreferencesSource,
    /setPreference\(PREF_SYNC_BACKEND_CONFIGS,\s*settings\.backendConfigs\)/,
    'background sync normalization should only persist normalized backend configs through the shared settings shape',
  );
  assert.match(
    assistantSyncSource,
    /setPreference\(PREF_SYNC_BACKEND_KIND,\s*configuredSyncBackendKind\)/,
    'assistant settings save path should persist the explicit configured backend kind rather than the effective fallback backend',
  );
  assert.doesNotMatch(
    assistantSyncSource,
    /draftEffectiveSyncBackendKind/,
    'assistant settings sync subtree should not keep a second draft-derived effective backend authority once runtime status owns effective backend truth',
  );
  assert.match(assistantSyncSource, /PREF_SYNC_BACKEND_CONFIGS/);
});
