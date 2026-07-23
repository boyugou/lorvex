import assert from 'node:assert/strict';
import test from 'node:test';

import { readTypeScriptSources } from './shared.mjs';

test('missing filesystem backend root path adopts the default path through the shared backend resolver', () => {
  const syncBackendPreferencesSource = readTypeScriptSources('app/src/lib/syncBackend/preferences.ts');
  const backgroundSyncPreferencesSource = readTypeScriptSources('app/src/lib/sync/preferences.ts');
  const assistantSyncBootstrapSource = readTypeScriptSources(
    'app/src/components/settings/controller/assistant/sync/bootstrap.ts',
  );

  assert.match(
    syncBackendPreferencesSource,
    /defaultFilesystemBridgeRootPath: string \| null/,
    'sync backend resolver should accept a filesystem-root fallback path',
  );
  assert.match(
    syncBackendPreferencesSource,
    /const normalizedRootPath = options\.defaultFilesystemBridgeRootPath\?\.trim\(\) \?\? '';/,
    'shared backend resolver should normalize the optional filesystem-root fallback path once',
  );
  assert.match(
    syncBackendPreferencesSource,
    /const needsDefaultFilesystemBridgeRootPath = Boolean\([\s\S]*backendConfigsState\.missingFilesystemRootPath[\s\S]*\);/,
    'shared backend resolver should only adopt the default filesystem root path when the active filesystem backend is still missing one',
  );
  assert.match(
    backgroundSyncPreferencesSource,
    /const defaultFilesystemBridgeRootPath = await getDefaultFilesystemBridgeRootPath\(\)\.catch\(\(\) => null\);/,
    'background sync should fail closed when loading the default filesystem root path',
  );
  assert.match(
    backgroundSyncPreferencesSource,
    /const resolvedSettings = resolveStoredSyncBackendSettings\(\{[\s\S]*defaultFilesystemBridgeRootPath,[\s\S]*\}\);/,
    'background sync should route stored backend preference recovery through the shared resolver',
  );
  assert.match(
    assistantSyncBootstrapSource,
    /const defaultFilesystemBridgeRootPath = await getDefaultFilesystemBridgeRootPath\(\);/,
    'assistant settings bootstrap should load the default filesystem root path for first-run backend resolution',
  );
  assert.match(
    assistantSyncBootstrapSource,
    /setDefaultFilesystemBridgeRootPath\(defaultFilesystemBridgeRootPath\?\.trim\(\) \?\? ''\)/,
    'assistant settings bootstrap should store the normalized default filesystem root path for the UI',
  );
  assert.match(
    assistantSyncBootstrapSource,
    /if \(resolvedSettings\.shouldPersistNormalized\) \{[\s\S]*setPreference\(PREF_SYNC_BACKEND_CONFIGS, resolvedSettings\.settings\.backendConfigs\)/,
    'assistant settings bootstrap should persist normalized backend configs after shared resolution repairs the filesystem root path',
  );
});
