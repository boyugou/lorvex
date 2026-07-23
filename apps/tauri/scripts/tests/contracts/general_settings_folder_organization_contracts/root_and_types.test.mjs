import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';

test('general settings types and composition are properly organized', () => {
  const generalTypesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/types.ts'),
    'utf8',
  );

  assert.match(
    generalTypesSource,
    /export type DesktopCloseActionPreference = 'quit' \| 'hide_to_tray';/,
    'general settings types should own the canonical desktop close-action union',
  );

  // GeneralSettingsSection.tsx was removed in the scroll-spy migration.
  // SettingsView now renders AppearanceSettingsSection and GeneralPreferencesSection
  // directly with scroll-spy section wrappers instead of delegating through a
  // composition root.
  const settingsViewSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/SettingsView.tsx'),
    'utf8',
  );

  assert.match(
    settingsViewSource,
    /import \{ AppearanceSettingsSection \} from '\.\/settings\/appearance\/AppearanceSettingsSection';/,
    'SettingsView should import AppearanceSettingsSection directly',
  );
  assert.match(
    settingsViewSource,
    /import \{ GeneralPreferencesSection \} from '\.\/settings\/general\/GeneralPreferencesSection';/,
    'SettingsView should import GeneralPreferencesSection directly',
  );
  assert.match(
    settingsViewSource,
    /id="settings-section-general"/,
    'SettingsView wraps general section with scroll-spy ID',
  );
  assert.match(
    settingsViewSource,
    /id="settings-section-appearance"/,
    'SettingsView wraps appearance section with scroll-spy ID',
  );
});
