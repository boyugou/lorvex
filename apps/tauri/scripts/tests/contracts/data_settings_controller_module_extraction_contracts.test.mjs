import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, readTypeScriptSources } from './shared.mjs';

test('SettingsView delegates data settings workflows to a dedicated controller module', () => {
  const settingsViewSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/SettingsView.tsx'),
    'utf8',
  );
  const dataControllerRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/useDataSettingsController.ts'),
    'utf8',
  );
  const dataControllerSource = readTypeScriptSources(
    'app/src/components/settings/controller/useDataSettingsController.ts',
    'app/src/components/settings/controller/data',
  );

  assert.match(
    settingsViewSource,
    /import \{ useDataSettingsController \} from '\.\/settings\/controller\/useDataSettingsController';/,
    'SettingsView should import the dedicated data settings controller',
  );
  assert.match(
    settingsViewSource,
    /const dataSettings = useDataSettingsController\(\{[\s\S]*settingsMountedRef,[\s\S]*}\);/s,
    'SettingsView should source data settings state from the dedicated controller',
  );
  assert.doesNotMatch(
    settingsViewSource,
    /const handleExportSnapshot = async \(\)|const handleImportSnapshot = async \(\)|const handleClearErrorLogs = async \(\)|const \[entries, changelog, syncEvents\] = await Promise\.all\(\[\s*getErrorLogs\(200\),\s*getChangelog\(120\),\s*getRecentSyncEvents\(120\),\s*\]\);/s,
    'SettingsView should not keep data-domain snapshot or diagnostics implementations after controller extraction',
  );

  assert.match(dataControllerRootSource, /export function useDataSettingsController\(/);
  assert.match(dataControllerRootSource, /import \{[\s\S]*useDataDiagnosticsControls[\s\S]*\} from '\.\/data\/diagnostics';/);
  assert.match(dataControllerRootSource, /import \{[\s\S]*useDataSnapshotControls[\s\S]*\} from '\.\/data\/snapshot';/);
  assert.doesNotMatch(
    dataControllerRootSource,
    /const handleExportSnapshot = async \(\)|const handleImportSnapshot = async \(\)|const handleClearErrorLogs = async \(\)|const \[entries, changelog, syncEvents\] = await Promise\.all\(\[\s*getErrorLogs\(200\),\s*getChangelog\(120\),\s*getRecentSyncEvents\(120\),\s*\]\);/s,
    'useDataSettingsController root should not inline snapshot or diagnostics implementations after helper extraction',
  );
  assert.match(dataControllerSource, /export function useDataSnapshotActions\(/);
  assert.match(dataControllerSource, /export function useSnapshotPayloadActions\(/);
  assert.match(dataControllerSource, /export function useSnapshotImportAction\(/);
  assert.match(dataControllerSource, /export function useDataDiagnosticsRefresh\(/);
  assert.match(dataControllerSource, /export function useDataDiagnosticsActions\(/);
  assert.match(dataControllerSource, /export function useRecentLogs\(/);
  assert.match(
    dataControllerSource,
    /const \[entries, changelog, (?:syncEvents|filteredSyncEvents)\] = await Promise\.all\(\[\s*(?:shouldIncludeErrorLogs[\s\S]*?:\s*Promise\.resolve\(\[\]\),|getErrorLogs\(200,\s*\{\s*sinceIso,\s*sourceDeviceId\s*\}\),)\s*getChangelog\(120,\s*\{\s*sinceIso,\s*sourceDeviceId\s*\}\),\s*(?:getRecentOutboxEntries\(120\)|loadFilteredRecentSyncEvents\(\{[\s\S]*?\}\)),\s*\]\);/s,
    'data diagnostics refresh should own the filtered error-log, changelog, and outbox fan-out after controller extraction',
  );
  assert.match(dataControllerSource, /const handleClearErrorLogs = useCallback\(async \(\) => \{/);
  assert.match(dataControllerSource, /const snapshotPreview = useMemo\(/);
  assert.match(dataControllerSource, /const snapshotControls = useDataSnapshotControls\(/);
});
