import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function readTypeScriptTree(relativeRoot) {
  const absoluteRoot = path.join(repoRoot, relativeRoot);
  const entries = fs.readdirSync(absoluteRoot, { withFileTypes: true });
  return entries
    .flatMap((entry) => {
      const relativePath = path.join(relativeRoot, entry.name);
      if (entry.isDirectory()) return [readTypeScriptTree(relativePath)];
      if (!entry.name.endsWith('.ts') && !entry.name.endsWith('.tsx')) return [];
      return [fs.readFileSync(path.join(repoRoot, relativePath), 'utf8')];
    })
    .join('\n');
}

test('data settings UI is organized as a folder-backed subsystem with snapshot, diagnostics, and about panels', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/DataSettingsSection.tsx'),
    'utf8',
  );
  const snapshotRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/SnapshotPanel.tsx'),
    'utf8',
  );
  const snapshotPayloadSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/data/snapshot/actions/payload.ts'),
    'utf8',
  );
  const settingsUtilsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/settingsUtils.ts'),
    'utf8',
  );
  const snapshotImportCommandSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/data/snapshot/import.rs'),
    'utf8',
  );
  const snapshotExportCommandSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/data/snapshot/export.rs'),
    'utf8',
  );
  const diagnosticsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/DiagnosticsPanel.tsx'),
    'utf8',
  );
  const diagnosticsPanelTreeSource = [
    diagnosticsSource,
    readTypeScriptTree('app/src/components/settings/data/diagnostics-panel'),
  ].join('\n');
  const aboutSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/AboutPanel.tsx'),
    'utf8',
  );
  const typesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/types.ts'),
    'utf8',
  );

  assert.match(
    rootSource,
    /import \{ SnapshotPanel \} from '\.\/SnapshotPanel';/,
    'Data settings root should delegate snapshot UI to a dedicated panel module',
  );
  assert.match(
    rootSource,
    /import \{ DiagnosticsPanel \} from '\.\/DiagnosticsPanel';/,
    'Data settings root should delegate diagnostics UI to a dedicated panel module',
  );
  assert.match(
    rootSource,
    /import \{ AboutPanel \} from '\.\/AboutPanel';/,
    'Data settings root should delegate about copy to a dedicated panel module',
  );
  assert.match(
    rootSource,
    /import \{ DangerZonePanel \} from '\.\/DangerZonePanel';/,
    'Data settings root should include a danger zone panel',
  );

  assert.match(
    snapshotRootSource,
    /onExportSnapshot|onImportSnapshot/,
    'SnapshotPanel should own export and import actions',
  );
  assert.match(
    snapshotRootSource,
    /t\('settings\.snapshotZipHelper'\)/,
    'SnapshotPanel should localize the ZIP snapshot import affordance explicitly',
  );
  assert.match(
    snapshotPayloadSource,
    /open\(\{[\s\S]*filters:\s*\[\{\s*name:\s*'ZIP',\s*extensions:\s*\['zip'\]\s*}\]/,
    'snapshot payload controller should restrict import selection to ZIP archives in the native dialog',
  );
  assert.match(
    snapshotPayloadSource,
    /save\(\{[\s\S]*filters:\s*\[\{\s*name:\s*'ZIP Archive',\s*extensions:\s*\['zip'\]\s*}\]/,
    'snapshot payload controller should restrict export save selection to ZIP archives in the native dialog',
  );
  assert.match(
    snapshotRootSource,
    /t\('settings\.revealInFolder'\)/,
    'SnapshotPanel should use platform-neutral reveal copy for exported snapshots',
  );
  assert.match(
    snapshotRootSource,
    /snapshotPreview\.fileName/,
    'SnapshotPanel should own selected snapshot preview rendering',
  );
  assert.match(
    snapshotRootSource,
    /entities_created|entities_updated|blobs_restored/,
    'SnapshotPanel should own import summary rendering for zip snapshots',
  );
  assert.match(
    settingsUtilsSource,
    /export function extractSnapshotFileName\(filePath: string\): string \| null \{/,
    'settings utils should own a shared snapshot file-name extractor',
  );
  assert.match(
    snapshotPayloadSource,
    /extractSnapshotFileName\(filePath\)/,
    'snapshot payload controller should reuse the shared snapshot file-name extractor',
  );
  assert.match(
    snapshotImportCommandSource,
    /validate_snapshot_zip_path\(&zip_path, &file_path\)\?/,
    'snapshot import command should validate the ZIP archive at the command boundary',
  );
  assert.match(
    snapshotImportCommandSource,
    /Snapshot import requires a \.zip archive|Snapshot import requires a valid ZIP archive/,
    'snapshot import command should reject non-ZIP paths before store import',
  );
  assert.match(
    snapshotExportCommandSource,
    /normalize_export_zip_path\(output_path\)\?/,
    'snapshot export command should normalize the ZIP archive path at the command boundary',
  );
  assert.match(
    snapshotExportCommandSource,
    /format!\("\{file_name\}\.zip"\)/,
    'snapshot export command should append a .zip suffix when the chosen export path lacks one',
  );

  assert.match(
    diagnosticsPanelTreeSource,
    /settings\.errorLogsScopeHint/,
    'Diagnostics panel subsystem should own the error-log scope explanation',
  );
  assert.match(
    diagnosticsPanelTreeSource,
    /errorLevelPillClass/,
    'Diagnostics panel subsystem should own diagnostics log severity rendering',
  );

  assert.match(
    aboutSource,
    /settings\.aboutText/,
    'About panel should own about-copy rendering',
  );
  assert.match(
    aboutSource,
    /settings\.aboutFeedback/,
    'About panel should link to feedback channel',
  );

  assert.match(
    typesSource,
    /export interface SnapshotStatus \{/,
    'Data settings types module should own snapshot status transport types',
  );
  assert.match(
    typesSource,
    /export interface RecentLogItem \{/,
    'Data settings types module should own merged recent-log item types',
  );
});
