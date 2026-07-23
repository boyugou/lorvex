import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readAppSources, repoRoot, readTypeScriptSources } from './shared.mjs';

test('sidebar visible module bootstrap uses the shared parser across App, Sidebar, and the general settings controller', () => {
  const helperText = fs.readFileSync(path.join(repoRoot, 'app/src/lib/sidebarModules.ts'), 'utf8');
  const appText = readAppSources();
  const sidebarText = readTypeScriptSources(
    'app/src/components/Sidebar.tsx',
    'app/src/components/sidebar',
  );
  const generalControllerText = readTypeScriptSources(
    'app/src/components/settings/controller/useGeneralSettingsController.ts',
    'app/src/components/settings/controller/general',
  );

  assert.match(
    helperText,
    /export function parseSidebarVisibleModulesPreference\(raw: string \| null \| undefined\): SidebarModule\[] \{/,
    'sidebarModules.ts should expose a shared persisted sidebar-module parser (backward compat)',
  );
  assert.match(
    helperText,
    /export function parseSidebarModuleConfig\(raw: string \| null \| undefined\): SidebarModuleConfig \{/,
    'sidebarModules.ts should expose the 3-state config parser',
  );
  assert.doesNotMatch(
    helperText,
    /legacySecondaryOnly|Backward compatibility: old values only contained secondary modules/,
    'sidebarModules.ts should not keep the removed secondary-only legacy compatibility branch',
  );
  assert.match(
    appText,
    /usePreference\(\s*PREF_SIDEBAR_VISIBLE_MODULES,\s*parseSidebarVisibleModulesPreference,/,
    'App should derive visible sidebar modules from the shared flat parser (navigation guard)',
  );
  assert.match(
    sidebarText,
    /usePreference\(\s*PREF_SIDEBAR_VISIBLE_MODULES,\s*parseSidebarModuleConfig,/,
    'Sidebar controller should derive module config from the 3-state parser',
  );
  assert.match(
    generalControllerText,
    /parseSidebarModuleConfig\(sidebarModulesRaw\)/,
    'general settings controller should bootstrap sidebar module config from the 3-state parser',
  );
  assert.doesNotMatch(
    appText,
    /normalizeSidebarModules\(JSON\.parse\(sidebarVisibleModulesRaw\)\)/,
    'App should not inline sidebar module JSON parsing outside the shared helper',
  );
  assert.doesNotMatch(
    sidebarText,
    /normalizeSidebarModules\(JSON\.parse\(sidebarVisibleModulesRaw\)\)/,
    'Sidebar should not inline sidebar module JSON parsing outside the shared helper',
  );
});
