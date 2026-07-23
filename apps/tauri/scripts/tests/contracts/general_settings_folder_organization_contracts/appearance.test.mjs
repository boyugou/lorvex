import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from '../shared.mjs';

test('general settings appearance subtree stays modular and folder-backed', () => {
  const appearanceRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/appearance/AppearanceSettingsSection.tsx'),
    'utf8',
  );
  const appearanceCatalogSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/appearance/catalog.ts'),
    'utf8',
  );
  const appearanceCardsModuleSource = readTypeScriptSources(
    'app/src/components/settings/appearance/cards',
  );

  // Appearance section renders inline grids directly (no studio dialog layer)
  assert.match(
    appearanceRootSource,
    /import[\s\S]*useTheme[\s\S]*from ['"](?:@\/lib\/theme|\.\.\/\.\.\/\.\.\/lib\/theme)['"];/,
    'Appearance section should use useTheme directly without a controller layer',
  );
  assert.match(
    appearanceRootSource,
    /import[\s\S]*ThemeOptionLane[\s\S]*from '\.\/cards\/themeLane';/,
    'Appearance section should render theme lanes inline',
  );
  assert.doesNotMatch(
    appearanceRootSource,
    /AppearanceStudioDialog|useAppearanceStudioController|showAppearanceStudio/,
    'Appearance section should not reference the removed studio system',
  );

  // Catalog owns theme preview palettes
  assert.match(
    appearanceCatalogSource,
    /\bTHEME_PREVIEW\b/,
    'Appearance catalog should own theme preview palettes',
  );

  // APPEARANCE_PROFILE_PREVIEW and APPEARANCE_PROFILE_INTENT_KEYS were removed
  assert.doesNotMatch(
    appearanceCatalogSource,
    /APPEARANCE_PROFILE_PREVIEW/,
    'Appearance catalog should not contain removed APPEARANCE_PROFILE_PREVIEW',
  );
  assert.doesNotMatch(
    appearanceCatalogSource,
    /APPEARANCE_PROFILE_INTENT_KEYS/,
    'Appearance catalog should not contain removed APPEARANCE_PROFILE_INTENT_KEYS',
  );

  // No cards barrel is needed: the section imports the dedicated theme-lane
  // module directly.
  assert.ok(
    !fs.existsSync(path.join(repoRoot, 'app/src/components/settings/appearance/cards.tsx')),
    'Appearance cards root should not exist; direct submodule imports keep the boundary explicit',
  );

  // Cards subtree owns component implementations
  assert.match(
    appearanceCardsModuleSource,
    /export function ThemeOptionLane\(/,
    'Appearance cards subtree should own theme lane rendering',
  );

  // profileCard.tsx was removed
  const profileCardPath = path.join(repoRoot, 'app/src/components/settings/appearance/cards/profileCard.tsx');
  assert.ok(
    !fs.existsSync(profileCardPath),
    'profileCard.tsx should not exist — appearance profile cards were removed',
  );

  // Studio directory should not exist after simplification
  const studioDir = path.join(repoRoot, 'app/src/components/settings/appearance/studio');
  assert.ok(
    !fs.existsSync(studioDir),
    'Studio directory should not exist — themes and profiles are rendered inline',
  );

  // Session storage module should not exist — no search or recent themes tracking
  const sessionFile = path.join(repoRoot, 'app/src/components/settings/appearance/session.ts');
  assert.ok(
    !fs.existsSync(sessionFile),
    'Session module should not exist — search and recent-theme tracking were removed',
  );
});
