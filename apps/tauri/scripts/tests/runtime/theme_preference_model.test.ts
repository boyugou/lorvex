import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  DEFAULT_APPEARANCE_PROFILE,
  DEFAULT_THEME_MODE,
  normalizeStoredAppearanceProfilePreference,
  normalizeStoredThemePreference,
} from '../../../app/src/lib/theme/model';

test('theme preference normalization accepts canonical JSON strings and rejects bare strings', () => {
  assert.deepEqual(
    normalizeStoredThemePreference('"dark"'),
    { mode: 'dark', shouldMigrate: false },
  );
  assert.deepEqual(
    normalizeStoredThemePreference('dark'),
    { mode: DEFAULT_THEME_MODE, shouldMigrate: true },
  );
});

test('theme preference normalization fails closed for malformed payloads', () => {
  assert.deepEqual(
    normalizeStoredThemePreference('{oops'),
    { mode: DEFAULT_THEME_MODE, shouldMigrate: true },
  );
});

test('appearance profile normalization accepts canonical JSON strings and rejects bare strings', () => {
  assert.deepEqual(
    normalizeStoredAppearanceProfilePreference('"studio"'),
    { profile: 'studio', shouldMigrate: false },
  );
  assert.deepEqual(
    normalizeStoredAppearanceProfilePreference('studio'),
    { profile: DEFAULT_APPEARANCE_PROFILE, shouldMigrate: true },
  );
});

test('appearance profile normalization falls back for invalid payloads', () => {
  assert.deepEqual(
    normalizeStoredAppearanceProfilePreference('"not-real"'),
    { profile: DEFAULT_APPEARANCE_PROFILE, shouldMigrate: true },
  );
});

test('appearance settings theme writes use one persistence path for undo safety', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/settings/appearance/AppearanceSettingsSection.tsx'),
    'utf8',
  );

  assert.match(source, /setMode\(nextMode, \{ persist: false \}\)/);
  assert.match(source, /onUndoValue/);
  assert.match(source, /setMode\(previousMode \?\? DEFAULT_THEME_MODE, \{ persist: false \}\)/);
  assert.doesNotMatch(source, /second write harmless/);
});
