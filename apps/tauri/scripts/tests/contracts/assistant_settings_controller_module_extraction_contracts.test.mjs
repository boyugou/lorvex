import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, readTypeScriptSources } from './shared.mjs';

test('SettingsView delegates assistant sync and MCP orchestration to a dedicated assistant settings controller', () => {
  const settingsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/SettingsView.tsx'),
    'utf8',
  );
  const controllerRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/useAssistantSettingsController.ts'),
    'utf8',
  );
  const controllerSource = readTypeScriptSources(
    'app/src/components/settings/controller/useAssistantSettingsController.ts',
    'app/src/components/settings/controller/assistant',
  );

  assert.match(
    settingsSource,
    /import \{ useAssistantSettingsController \} from '\.\/settings\/controller\/useAssistantSettingsController';/,
    'SettingsView should import the assistant settings controller from the dedicated controller folder',
  );
  assert.match(
    settingsSource,
    /const assistantSettings = useAssistantSettingsController\(\{/,
    'SettingsView should instantiate the dedicated assistant settings controller',
  );
  assert.match(
    settingsSource,
    /assistantSettings\.sync/s,
    'SettingsView should pass assistant controller sync output into section components',
  );
  assert.match(
    settingsSource,
    /assistantSettings\.mcp/s,
    'SettingsView should pass assistant controller MCP output into section components',
  );
  assert.doesNotMatch(
    settingsSource,
    /runSyncBackendNow\(|getMcpServerStatus\(|getPendingOutboxEntries\(|getSyncStatus\(/,
    'SettingsView should stop owning assistant sync and MCP runtime orchestration directly once the controller exists',
  );

  assert.match(
    controllerRootSource,
    /export function useAssistantSettingsController\(/,
    'assistant settings controller should expose a dedicated hook',
  );
  assert.match(
    controllerRootSource,
    /import \{ useAssistantSyncController \} from '\.\/assistant\/sync';/,
    'assistant settings controller root should delegate sync orchestration to a dedicated assistant sync module',
  );
  assert.match(
    controllerRootSource,
    /import \{ useAssistantMcpController \} from '\.\/assistant\/mcp';/,
    'assistant settings controller root should delegate MCP orchestration to a dedicated assistant MCP module',
  );
  assert.doesNotMatch(
    controllerRootSource,
    /runSyncBackendNow\(|getMcpServerStatus\(|getPendingOutboxEntries\(|getSyncStatus\(/,
    'assistant settings controller root should remain a composition boundary after subsystem extraction',
  );
  assert.match(
    controllerSource,
    /runSyncBackendNow\(/,
    'assistant settings sync subtree should own manual sync execution',
  );
  assert.match(
    controllerSource,
    /createMcpServerStatusQueryOptions\(/,
    'assistant settings subtree should own MCP status loading through the shared query-options helper',
  );
  assert.doesNotMatch(
    controllerSource,
    /getRemote providerStatus\(/,
    'assistant settings sync subtree should not keep retired Remote provider diagnostics loading',
  );
  assert.match(
    controllerSource,
    /getPendingOutboxEntries\(5\)/,
    'assistant settings sync subtree should own sync queue preview loading',
  );
  assert.match(
    controllerSource,
    /getSyncStatus\(/,
    'assistant settings sync subtree should own sync status loading',
  );
});
