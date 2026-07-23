import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, readRustSources, readTypeScriptSources } from './shared.mjs';

test('desktop close action contract keeps hide-to-tray recoverable and aligned across the general settings controller and Rust', () => {
  const generalControllerSource = readTypeScriptSources(
    'app/src/components/settings/controller/useGeneralSettingsController.ts',
    'app/src/components/settings/controller/general',
  );
  const generalTypesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/types.ts'),
    'utf8',
  );
  const desktopBehaviorSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/DesktopBehaviorPanel.tsx'),
    'utf8',
  );
  const generalCatalogSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/catalog.ts'),
    'utf8',
  );
  const rustSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/desktop_close_policy.rs'),
    'utf8',
  );
  const desktopShellSource = readRustSources('app/src-tauri/src/desktop_shell');

  assert.match(
    generalTypesSource,
    /export type DesktopCloseActionPreference = 'quit' \| 'hide_to_tray';/,
    'General settings types should keep the canonical desktop close action union',
  );
  assert.match(
    generalCatalogSource,
    /value: 'hide_to_tray'[\s\S]*value: 'quit'/,
    'general settings catalog should continue exposing both close action options',
  );
  assert.match(
    desktopBehaviorSource,
    /DESKTOP_CLOSE_ACTION_OPTIONS\.map\(/,
    'Desktop behavior panel should render close action options from the shared general settings catalog',
  );
  assert.match(
    rustSource,
    /const DESKTOP_CLOSE_ACTION_QUIT: &str = "quit";[\s\S]*const DESKTOP_CLOSE_ACTION_HIDE_TO_TRAY: &str = "hide_to_tray";/s,
    'Rust close policy parser should keep the canonical persisted values',
  );
  assert.match(
    generalControllerSource,
    /ensureTrayIconVisibleForHideToTray: \(\) => ensureTrayIconVisibleForHideToTray\(\{/,
    'general settings controller should route hide-to-tray autosave through the shared tray-visibility guard',
  );
  assert.match(
    generalControllerSource,
    /await setTrayIconVisibility\(true\);[\s\S]*await setDeviceState\(\s*DEV_MENU_BAR_ICON_VISIBLE,\s*true\s*\);[\s\S]*updateTrayIconVisible\(true\);/s,
    'Hide-to-tray guard should restore both runtime tray visibility and the persisted device state',
  );
  assert.match(
    generalControllerSource,
    /if\s*\([\s\S]*args\.runtimeClass === 'desktop'[\s\S]*args\.trayPresentationKind !== 'none'[\s\S]*args\.desktopCloseActionDirty[\s\S]*args\.desktopCloseAction === 'hide_to_tray'[\s\S]*\)\s*\{[\s\S]*await args\.ensureTrayIconVisibleForHideToTray\(\);[\s\S]*\}/,
    'Desktop close autosave should ensure tray visibility before persisting hide-to-tray',
  );
  assert.match(
    rustSource,
    /DesktopCloseAction::HideToTray => \{\s*if let Some\(tray\) = app_handle\.tray_by_id\("lorvex-tray"\) \{\s*let _ = tray\.set_visible\(true\);\s*\}\s*hide_auxiliary_desktop_windows\(&app_handle\);\s*let _ = main_clone\.hide\(\);/s,
    'Main close-to-tray should hide auxiliary desktop windows before hiding the main window',
  );
  assert.match(
    desktopShellSource,
    /pub\(crate\)\s+fn\s+hide_auxiliary_desktop_windows\(\s*app: &tauri::AppHandle,?\s*\)\s*\{[\s\S]*hide_popover_window\(app\.clone\(\)\)/s,
    'Shared auxiliary hide helper should route the popover teardown through the popover hide command',
  );
});
