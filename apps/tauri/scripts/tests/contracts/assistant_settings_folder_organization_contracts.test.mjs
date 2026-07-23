import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('assistant settings UI is organized as a folder-backed subsystem with sync and MCP modules', () => {
  // SettingsView directly composes the assistant sub-sections (McpSetupSection + SyncSettingsPanel).
  // No intermediate wrapper component is needed — SettingsView IS the composition root.
  const settingsViewSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/SettingsView.tsx'),
    'utf8',
  );
  const typeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/assistant/types.ts'),
    'utf8',
  );
  const syncSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/assistant/sync-settings/SyncSettingsPanel.tsx'),
    'utf8',
  );
  const syncMethodSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/assistant/sync-settings/SyncMethodCard.tsx'),
    'utf8',
  );
  const syncBackendSelectorSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/assistant/sync-settings/SyncBackendSelector.tsx'),
    'utf8',
  );
  const backendContextSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/assistant/sync-settings/backendContext.ts'),
    'utf8',
  );
  const syncDiagnosticsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/assistant/sync-settings/SyncDiagnosticsPanel.tsx'),
    'utf8',
  );
  const syncQueueSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/assistant/sync-settings/SyncQueuePreview.tsx'),
    'utf8',
  );
  const mcpSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/assistant/McpSetupSection.tsx'),
    'utf8',
  );

  // SettingsView imports assistant sub-sections directly
  assert.match(
    settingsViewSource,
    /import \{[\s\S]*McpSetupSection[\s\S]*\} from '\.\/settings\/assistant\/McpSetupSection';/,
    'SettingsView should import McpSetupSection from settings/assistant/McpSetupSection',
  );
  assert.match(
    settingsViewSource,
    /import \{[\s\S]*SyncSettingsPanel[\s\S]*\} from '\.\/settings\/assistant\/sync-settings\/SyncSettingsPanel';/,
    'SettingsView should import SyncSettingsPanel from settings/assistant/sync-settings/SyncSettingsPanel',
  );

  // Type system enforces grouped view-model
  assert.match(typeSource, /export interface AssistantSettingsViewModel \{/);
  assert.match(typeSource, /export interface AssistantSyncSettingsModel \{/);
  assert.match(typeSource, /export interface AssistantMcpSetupModel \{/);

  // Sync settings panel delegates to sub-components
  assert.match(syncSource, /sync: AssistantSyncSettingsModel;/);
  assert.match(syncSource, /import \{ SyncMethodCard \} from '\.\/SyncMethodCard';/);
  assert.match(syncSource, /import \{ SyncDiagnosticsPanel \} from '\.\/SyncDiagnosticsPanel';/);
  assert.match(syncSource, /import \{ SyncQueuePreview \} from '\.\/SyncQueuePreview';/);
  assert.doesNotMatch(
    syncSource,
    /availableSyncBackendDescriptors\.map\(|syncBackendUsesFilesystemRootPathEditor\(|filesystem_bridge_last_pull_cursor_malformed/,
    'sync-settings root should stay a composition boundary after folder extraction',
  );
  assert.match(syncMethodSource, /<SyncBackendSelector/);
  assert.match(syncBackendSelectorSource, /availableSyncBackendDescriptors\.map\(/);
  assert.match(
    syncMethodSource,
    /import \{ resolveSyncSettingsBackendContext \} from '\.\/backendContext';/,
    'sync method card should resolve editor affordances through the dedicated backend-context helper',
  );
  assert.match(
    backendContextSource,
    /const backendKind = options\.draftConfiguredBackendKind \?\? null/,
    'backend-context helper should derive editor affordances from explicit draft configuration only',
  );
  assert.doesNotMatch(
    backendContextSource,
    /runtimeEffectiveBackendKind|runtime_effective/,
    'backend-context helper should not leak runtime-effective fallback into settings editor affordances',
  );
  assert.match(
    backendContextSource,
    /sync_backend_kind_effective === backendKind/,
    'runtime diagnostics helper should gate backend-specific diagnostics to the effective runtime backend context',
  );
  assert.match(
    syncBackendSelectorSource,
    /draftSyncBackendKind === descriptor\.kind/,
    'sync method selection buttons should reflect explicit draft configuration rather than effective fallback',
  );
  assert.match(
    syncMethodSource,
    /resolveSyncSettingsBackendContext\(/,
    'sync method card should centralize explicit backend editor affordances instead of recomputing pseudo-selected backend state inline',
  );
  assert.match(
    syncMethodSource,
    /draftConfiguredBackendKind:\s*draftSyncBackendKind/s,
    'sync method card should pass only explicit draft configuration into the editor backend-context helper',
  );
  assert.match(
    syncDiagnosticsSource,
    /shouldShowRuntimeBackendDiagnostics\(/,
    'sync diagnostics panel should centralize runtime-backend diagnostics gating instead of inlining backend-fallback semantics',
  );
  assert.match(syncMethodSource, /syncBackendConfigs\.filesystem_bridge\.rootPath/);
  assert.match(syncDiagnosticsSource, /syncStatus\.filesystem_bridge_last_pull_cursor_malformed/);
  assert.match(syncQueueSource, /syncPendingPreview\.map\(/);

  assert.match(
    typeSource,
    /export type AssistantSnippetKey =/,
    'assistant settings types module should own AssistantSnippetKey',
  );
  assert.match(mcpSource, /getClaudeDesktopConfigPathHint\(\)/);
  assert.match(mcpSource, /settings\.mcpClaudeDesktop/);
});

test('sync settings contract fixtures do not carry stale flat SyncSettingsPanel copies', () => {
  const fixtureRoots = [
    'scripts/tests/contracts/fixtures/sync-backend-profile-contract/pass',
    'scripts/tests/contracts/fixtures/sync-backend-profile-contract/fail-comment-settings-call',
  ];

  for (const fixtureRoot of fixtureRoots) {
    const staleFlatPath = path.join(
      repoRoot,
      fixtureRoot,
      'app/src/components/settings/assistant/SyncSettingsPanel.tsx',
    );
    const canonicalFolderPath = path.join(
      repoRoot,
      fixtureRoot,
      'app/src/components/settings/assistant/sync-settings/SyncSettingsPanel.tsx',
    );

    assert.equal(
      fs.existsSync(staleFlatPath),
      false,
      `${fixtureRoot} should not keep the stale flat SyncSettingsPanel fixture path`,
    );
    assert.equal(
      fs.existsSync(canonicalFolderPath),
      true,
      `${fixtureRoot} should mirror the production sync-settings folder layout`,
    );
  }
});
