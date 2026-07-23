import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, readTypeScriptSources } from './shared.mjs';

test('SettingsView delegates general settings bootstrap and autosave workflows to a dedicated controller module', () => {
  const settingsViewSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/SettingsView.tsx'),
    'utf8',
  );
  const generalControllerRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/useGeneralSettingsController.ts'),
    'utf8',
  );
  const generalControllerSource = readTypeScriptSources(
    'app/src/components/settings/controller/useGeneralSettingsController.ts',
    'app/src/components/settings/controller/general',
  );

  assert.match(
    settingsViewSource,
    /import \{ useGeneralSettingsController \} from '\.\/settings\/controller\/useGeneralSettingsController';/,
    'SettingsView should import the dedicated general settings controller',
  );
  assert.match(
    settingsViewSource,
    /const generalSettings = useGeneralSettingsController\(\{[\s\S]*runtimeClass,[\s\S]*trayPresentationKind,[\s\S]*supportsBiometricLock,[\s\S]*settingsMountedRef,[\s\S]*}\);/s,
    'SettingsView should source general settings state from the dedicated controller',
  );
  assert.match(
    settingsViewSource,
    /const loaded = generalSettings\.ready && assistantSettings\.ready;/,
    'SettingsView should derive overall readiness from the general + assistant controller boundaries',
  );
  assert.doesNotMatch(
    settingsViewSource,
    /const logSettingsError = useCallback\(|const saveWorkingHours = async \(\)|const saveFocusCount = async \(\)|const ensureTrayIconVisibleForHideToTray = useCallback\(|const saveAdvanced = async \(\)|const handleAutostartToggle = async \(\)|const handleTrayIconToggle = async \(\)|const handleMemoryLockToggle = async \(\)|const toggleSidebarModule = \(|const resetSidebarModules = \(/s,
    'SettingsView should not keep general-domain bootstrap, autosave, toggle, or sidebar mutation logic after controller extraction',
  );

  assert.match(
    generalControllerRootSource,
    /export \{\s*useGeneralSettingsController\s*} from '\.\/general\/useGeneralSettingsController';/s,
    'general settings controller root should delegate to the folder-backed general controller module',
  );
  assert.doesNotMatch(
    generalControllerRootSource,
    /const settingsLoadSeqRef = useRef\(0\);|const toggleSidebarModule = useCallback\(\(moduleId: SidebarModule\) => \{|const persistAdvanced = useCallback\(async \(\) => \{|const \[workingHoursStart, setWorkingHoursStart\] = useState\('09:00'\);/,
    'general settings controller root should stay a thin facade instead of keeping controller internals inline',
  );
  assert.match(generalControllerSource, /const settingsLoadSeqRef = useRef\(0\);/);
  assert.match(generalControllerSource, /export async function loadGeneralSettingsSnapshot\(/);
  assert.match(generalControllerSource, /export async function saveAdvancedPreferences\(/);
  assert.match(generalControllerSource, /export async function persistAutostartPreference\(/);
  assert.match(generalControllerSource, /export async function persistTrayIconVisibility\(/);
  assert.match(generalControllerSource, /export function useGeneralSettingsState\(/);
  assert.match(generalControllerSource, /export function useGeneralSettingsPersistence\(/);
  assert.match(generalControllerSource, /const cycleSidebarModule = useCallback\(\(moduleId: SidebarModule\) => \{/);
});
