import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, readTypeScriptSources } from './shared.mjs';

test('assistant sync controller is organized as a folder-backed subsystem with focused runtime modules', () => {
  const syncRoot = path.join(repoRoot, 'app/src/components/settings/controller/assistant/sync');
  const actionsRoot = path.join(syncRoot, 'actions');
  const syncControllerSource = fs.readFileSync(path.join(syncRoot, 'useAssistantSyncController.ts'), 'utf8');
  const syncActionsSource = fs.readFileSync(path.join(syncRoot, 'actions.ts'), 'utf8');
  const syncIndexSource = fs.readFileSync(path.join(syncRoot, 'index.ts'), 'utf8');
  const syncTreeSource = readTypeScriptSources('app/src/components/settings/controller/assistant/sync');

  for (const fileName of ['actions.ts', 'autosave.ts', 'bootstrap.ts', 'presentation.ts', 'types.ts']) {
    assert.ok(
      fs.existsSync(path.join(syncRoot, fileName)),
      `assistant sync subsystem should include ${fileName}`,
    );
  }
  for (const fileName of ['bridge.ts', 'run.ts', 'status.ts', 'transport.ts', 'types.ts']) {
    assert.ok(
      fs.existsSync(path.join(actionsRoot, fileName)),
      `assistant sync actions subtree should include ${fileName}`,
    );
  }

  assert.equal(
    fs.existsSync(path.join(syncRoot, 'index.ts')),
    true,
    'assistant sync should expose a narrow index.ts barrel for controller imports',
  );
  assert.match(syncIndexSource, /export \{ useAssistantSyncController \} from '\.\/useAssistantSyncController';/);
  assert.match(syncControllerSource, /from '\.\/actions';/);
  assert.match(syncControllerSource, /from '\.\/autosave';/);
  assert.match(syncControllerSource, /from '\.\/bootstrap';/);
  assert.match(syncControllerSource, /from '\.\/presentation';/);
  assert.match(syncControllerSource, /from '\.\/types';/);
  assert.match(syncActionsSource, /from '\.\/actions\/bridge';/);
  assert.match(syncActionsSource, /from '\.\/actions\/run';/);
  assert.match(syncActionsSource, /from '\.\/actions\/status';/);
  assert.match(syncActionsSource, /from '\.\/actions\/transport';/);
  assert.match(syncActionsSource, /from '\.\/actions\/types';/);
  assert.doesNotMatch(
    syncControllerSource,
    /draftEffectiveSyncBackendKind/,
    'assistant sync controller should not expose a second draft-derived effective backend authority in the view model',
  );
  assert.match(syncControllerSource, /runtimeConfiguredSyncBackendKind/);
  assert.match(syncControllerSource, /runtimeEffectiveSyncBackendKind/);
  assert.match(
    syncTreeSource,
    /if \(syncBackendSaveState === 'saving'\) \{\s*toast\.info\(t\('common\.saving'\)\);/s,
    'assistant sync run action should block manual sync while settings autosave is still in flight',
  );
  assert.match(
    syncTreeSource,
    /buildSyncBackendConfig\(\{\s*backendKind:\s*runtimeEffectiveSyncBackendKind,/s,
    'assistant sync run action should use the persisted runtime-effective backend instead of a local fallback authority',
  );
  assert.match(
    syncTreeSource,
    /setConfiguredSyncBackendKind\(status\.sync_backend_kind as SyncBackendKind \| null\)/,
    'assistant sync status refresh should hydrate the draft selection from the persisted configured backend, not from runtime effective fallback',
  );
  assert.doesNotMatch(
    syncTreeSource,
    /draftEffectiveSyncBackendKind|resolveSyncBackend\(\{/,
    'assistant sync subtree should not reintroduce a local draft effective-backend resolver once runtime status owns effective backend truth',
  );
  assert.doesNotMatch(
    syncControllerSource,
    /getDefaultFilesystemBridgeRootPath\(|setPreference\('sync_enabled'/,
    'assistant sync index should stay a composition boundary once the runtime modules are split out',
  );
  assert.doesNotMatch(
    syncActionsSource,
    /runSyncBackendNow\(|setPreference\('sync_enabled'|getPendingSyncEvents\(/,
    'assistant sync actions root should stay a composition boundary once refresh, save, and run logic move into focused action modules',
  );

  assert.match(syncTreeSource, /runSyncBackendNow\(/);
  assert.match(syncTreeSource, /getDefaultFilesystemBridgeRootPath\(/);
  assert.doesNotMatch(syncTreeSource, /formatRemote providerDiagnosticValue\(/);
});
