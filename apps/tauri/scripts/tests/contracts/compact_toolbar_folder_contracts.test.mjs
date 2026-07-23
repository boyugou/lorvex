import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const ROOT_VIEW = 'app/src/components/quick-capture/CompactToolbar.tsx';
const TOOLBAR_FILES = [
  'app/src/components/quick-capture/toolbar/DatePills.tsx',
  'app/src/components/quick-capture/toolbar/DetectedDateChip.tsx',
  'app/src/components/quick-capture/toolbar/DurationDropdown.tsx',
  'app/src/components/quick-capture/toolbar/PriorityDropdown.tsx',
  'app/src/components/quick-capture/toolbar/TagsToggle.tsx',
  'app/src/components/quick-capture/toolbar/types.ts',
];
const EXTRACTED_COMPONENTS = [
  'DatePills',
  'InlineDetectedDateChip',
  'DurationDropdown',
  'PriorityDropdown',
  'TagsToggle',
  'SunChip',
];

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('CompactToolbar delegates controls to the quick-capture toolbar subtree', () => {
  const root = read(ROOT_VIEW);

  for (const relativePath of TOOLBAR_FILES) {
    assert.ok(
      fs.existsSync(path.join(repoRoot, relativePath)),
      `${relativePath} should exist as a focused quick-capture toolbar module`,
    );
  }

  for (const componentName of EXTRACTED_COMPONENTS) {
    assert.doesNotMatch(
      root,
      new RegExp(`function\\s+${componentName}\\b`),
      `${componentName} should not be implemented in the root CompactToolbar file`,
    );
  }

  for (const [componentName, moduleName] of [
    ['DatePills', 'DatePills'],
    ['InlineDetectedDateChip', 'DetectedDateChip'],
    ['DurationDropdown', 'DurationDropdown'],
    ['PriorityDropdown', 'PriorityDropdown'],
    ['TagsToggle', 'TagsToggle'],
  ]) {
    assert.match(
      root,
      new RegExp(`import\\s+\\{\\s*${componentName}\\s*\\}\\s+from\\s+'\\.\\/toolbar\\/${moduleName}';`),
      `${componentName} should be imported from the quick-capture toolbar subtree`,
    );
  }

  const rootLineCount = root.split(/\r?\n/).length;
  assert.ok(
    rootLineCount <= 180,
    `CompactToolbar root should stay a thin composition boundary, found ${rootLineCount} lines`,
  );
});
