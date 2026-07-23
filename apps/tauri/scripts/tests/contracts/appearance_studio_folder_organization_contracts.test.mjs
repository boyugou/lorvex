import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('appearance settings section renders inline theme and profile grids without a separate studio dialog', () => {
  const sectionSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/appearance/AppearanceSettingsSection.tsx'),
    'utf8',
  );

  // Should import directly from theme lib and cards — no studio controller layer
  assert.match(
    sectionSource,
    /import[\s\S]*useTheme[\s\S]*from ['"](?:@\/lib\/theme|\.\.\/\.\.\/\.\.\/lib\/theme)['"];/,
    'appearance section should use useTheme directly',
  );
  assert.match(
    sectionSource,
    /import[\s\S]*ThemeOptionLane[\s\S]*from '\.\/cards\/themeLane';/,
    'appearance section should import ThemeOptionLane for inline rendering',
  );

  // Should NOT have a studio dialog or controller
  assert.doesNotMatch(
    sectionSource,
    /AppearanceStudioDialog|useAppearanceStudioController|showAppearanceStudio/,
    'appearance section should not reference the deleted studio dialog or controller',
  );

  // The studio directory should not exist
  const studioDir = path.join(repoRoot, 'app/src/components/settings/appearance/studio');
  assert.ok(
    !fs.existsSync(studioDir),
    'studio directory should not exist after simplification',
  );
});
