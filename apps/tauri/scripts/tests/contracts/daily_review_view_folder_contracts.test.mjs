import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const ROOT_VIEW = 'app/src/components/DailyReviewView.tsx';
const CONTENT_FILES = [
  'app/src/components/daily-review/content/DaySummarySection.tsx',
  'app/src/components/daily-review/content/MoodEnergySection.tsx',
  'app/src/components/daily-review/content/ReflectionSection.tsx',
  'app/src/components/daily-review/content/SaveStreakSection.tsx',
];
const EXTRACTED_COMPONENTS = [
  'DaySummarySection',
  'MoodEnergySection',
  'ReflectionSection',
  'SaveStreakSection',
  'StatSummaryCard',
  'MiniTrend',
  'CollapsibleReflection',
];

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('DailyReviewView delegates section content to the daily-review content subtree', () => {
  const root = read(ROOT_VIEW);

  for (const relativePath of CONTENT_FILES) {
    assert.ok(
      fs.existsSync(path.join(repoRoot, relativePath)),
      `${relativePath} should exist as a focused Daily Review content module`,
    );
  }

  for (const componentName of EXTRACTED_COMPONENTS) {
    assert.doesNotMatch(
      root,
      new RegExp(`function\\s+${componentName}\\b`),
      `${componentName} should not be implemented in the root DailyReviewView file`,
    );
  }

  for (const componentName of ['DaySummarySection', 'MoodEnergySection', 'ReflectionSection', 'SaveStreakSection']) {
    assert.match(
      root,
      new RegExp(`import\\s+\\{\\s*${componentName}\\s*\\}\\s+from\\s+'\\.\\/daily-review\\/content\\/${componentName}';`),
      `${componentName} should be imported from the daily-review content subtree`,
    );
  }

  const rootLineCount = root.split(/\r?\n/).length;
  assert.ok(
    rootLineCount <= 220,
    `DailyReviewView root should stay a thin composition boundary, found ${rootLineCount} lines`,
  );
});
