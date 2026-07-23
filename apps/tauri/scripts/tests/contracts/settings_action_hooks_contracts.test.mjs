import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('data and native-calendar settings panels delegate write ownership to dedicated hooks/controllers', () => {
  const dangerZonePanelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/DangerZonePanel.tsx'),
    'utf8',
  );
  const dangerZoneActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/useDangerZoneActions.ts'),
    'utf8',
  );
  const retentionPanelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/RetentionSettingsPanel.tsx'),
    'utf8',
  );
  const retentionControllerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/useRetentionSettingsController.ts'),
    'utf8',
  );
  const nativeCalendarPanelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/calendar/NativeCalendarPanel.tsx'),
    'utf8',
  );
  const nativeCalendarControllerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/calendar/useNativeCalendarPanelController.ts'),
    'utf8',
  );
  const nativeCalendarControllerLogicSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/calendar/useNativeCalendarPanelController.logic.ts'),
    'utf8',
  );

  assert.match(
    dangerZonePanelSource,
    /import \{ useDangerZoneActions \} from '\.\/useDangerZoneActions';/,
    'Danger zone panel should delegate destructive reset actions to a dedicated hook',
  );
  assert.doesNotMatch(dangerZonePanelSource, /useQueryClient|resetPreferences\(|resetAllData\(/);
  assert.match(dangerZoneActionsSource, /export function useDangerZoneActions\(/);
  assert.match(dangerZoneActionsSource, /resetPreferences\(/);
  assert.match(dangerZoneActionsSource, /resetAllData\(/);

  assert.match(
    retentionPanelSource,
    /import \{ useRetentionSettingsController \} from '\.\/useRetentionSettingsController';/,
    'Retention settings panel should delegate preference loading and purge actions to a dedicated controller hook',
  );
  assert.doesNotMatch(retentionPanelSource, /getPreference\(|setPreference\(|purgeCancelledTasks\(|confirm\(/);
  assert.match(retentionControllerSource, /export function useRetentionSettingsController\(/);
  assert.match(retentionControllerSource, /usePreference\(/);
  assert.doesNotMatch(retentionControllerSource, /getPreference\(/);
  assert.match(retentionControllerSource, /usePreferenceMutationWithUndo\(/);
  assert.doesNotMatch(retentionControllerSource, /purgeCancelledTasks\(|confirm\(/);
  assert.match(retentionPanelSource, /<DangerZoneLink message=\{t\('settings\.purgeCancelledMoved'\)\} \/>/);

  assert.match(
    nativeCalendarPanelSource,
    /import \{ useNativeCalendarPanelController \} from '\.\/useNativeCalendarPanelController';/,
    'Native calendar panel should delegate device-state and sync mutations to a dedicated controller hook',
  );
  assert.doesNotMatch(nativeCalendarPanelSource, /useQuery\(|getDeviceState\(|setDeviceState\(|clearNativeCalendarEvents\(/);
  assert.match(nativeCalendarControllerSource, /export function useNativeCalendarPanelController\(/);
  assert.match(nativeCalendarControllerSource, /useQuery\(/);
  assert.match(nativeCalendarControllerSource, /setDeviceState\(/);
  assert.match(nativeCalendarControllerSource, /clearNativeCalendarPanelProviderEvents\(/);
  assert.match(nativeCalendarControllerLogicSource, /export async function clearNativeCalendarPanelProviderEvents\(/);
  assert.match(nativeCalendarControllerLogicSource, /clearNativeCalendarEvents\(clearProviderKind\)/);
  assert.match(nativeCalendarControllerLogicSource, /invalidateCalendarMutationQueries\(/);
});
