import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, readTypeScriptSources } from './shared.mjs';

test('settings refresh loops prevent overlapping async ticks across data diagnostics and assistant sync polling', () => {
  const dataControllerSource = readTypeScriptSources(
    'app/src/components/settings/controller/useDataSettingsController.ts',
    'app/src/components/settings/controller/data',
  );
  const assistantControllerSource = readTypeScriptSources(
    'app/src/components/settings/controller/useAssistantSettingsController.ts',
    'app/src/components/settings/controller/assistant',
  );

  assert.match(
    dataControllerSource,
    /const diagnosticsRefreshRunningRef = useRef\(false\);/,
    'data settings controller should track when a diagnostics refresh tick is already in flight',
  );
  assert.match(
    dataControllerSource,
    /const diagnosticsTick = useCallback\(\(\) => \{\s*if \(diagnosticsRefreshRunningRef\.current\) return;\s*diagnosticsRefreshRunningRef\.current = true;[\s\S]*?void refreshErrorLogs\(true\)[\s\S]*?diagnosticsRefreshRunningRef\.current = false;[\s\S]*?\}, \[refreshErrorLogs\]\);\s*useVisibilityGatedInterval\(diagnosticsTick, 30_000\);/s,
    'data settings controller background refresh should route diagnostics polling through one guarded visibility-gated tick',
  );
  assert.match(
    assistantControllerSource,
    /const assistantRefreshRunningRef = useRef\(false\);/,
    'assistant settings controller should track when a sync refresh tick is already in flight',
  );
  assert.match(
    assistantControllerSource,
    /const syncStatusTick = useCallback\(\(\) => \{/,
    'assistant settings controller should keep sync polling in a dedicated guarded tick callback',
  );
  assert.match(
    assistantControllerSource,
    /if \(!ready \|\| assistantRefreshRunningRef\.current\) return;/,
    'assistant settings controller polling should stay gated on readiness',
  );
  assert.match(
    assistantControllerSource,
    /void refreshSyncStatus\(\)/,
    'assistant settings controller polling should refresh sync status from the guarded tick',
  );
  assert.match(
    assistantControllerSource,
    /useVisibilityGatedInterval\(syncStatusTick, 30_000\)/,
    'assistant settings controller should poll sync status every 30 seconds through the shared visibility-gated interval hook',
  );
  assert.match(
    assistantControllerSource,
    /assistantRefreshRunningRef\.current = false;/,
    'assistant settings controller should release the in-flight polling guard after each tick',
  );
  assert.match(
    assistantControllerSource,
    /syncBackendDraftPendingRef\.current = backendKind;\s*setConfiguredSyncBackendKind\(backendKind\);/s,
    'assistant settings controller should mark the chosen backend as a pending draft before updating local state',
  );
  assert.match(
    assistantControllerSource,
    /if \(syncBackendDraftPendingRef\.current === null\) \{\s*setConfiguredSyncBackendKind\(status\.sync_backend_kind as SyncBackendKind \| null\);\s*\}/s,
    'assistant settings controller refresh should only hydrate configured sync backend when no unsaved backend draft is pending',
  );
  assert.match(
    assistantControllerSource,
    /if \(syncBackendDraftPendingRef\.current === configuredSyncBackendKind\) \{\s*syncBackendDraftPendingRef\.current = null;\s*\}/s,
    'assistant settings controller should clear the pending backend draft only after that exact backend has been persisted',
  );
});
