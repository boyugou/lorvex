import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('WeeklyReviewView is organized as a folder-backed subsystem with controller and content modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/WeeklyReviewView.tsx'), 'utf8');
  const controllerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/weekly-review/useWeeklyReviewController.ts'),
    'utf8',
  );
  const contentSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/weekly-review/WeeklyReviewContent.tsx'),
    'utf8',
  );
  const statCardSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/weekly-review/content/StatCard.tsx'),
    'utf8',
  );
  const reviewSectionSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/weekly-review/content/ReviewSection.tsx'),
    'utf8',
  );
  const stalledProjectRowSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/weekly-review/content/StalledListRow.tsx'),
    'utf8',
  );
  const deferredTaskRowSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/weekly-review/content/DeferredTaskRow.tsx'),
    'utf8',
  );

  assert.match(
    rootSource,
    /import WeeklyReviewContent from '\.\/weekly-review\/WeeklyReviewContent';/,
    'WeeklyReviewView root should render the dedicated weekly-review content module',
  );
  assert.match(
    rootSource,
    /useWeeklyReviewController\(props\)/,
    'WeeklyReviewView root should delegate review orchestration to the dedicated controller',
  );
  assert.match(
    controllerSource,
    /export function useWeeklyReviewController\(/,
    'WeeklyReviewView should keep review queries and interventions in a dedicated controller module',
  );
  assert.match(
    contentSource,
    /export default function WeeklyReviewContent/,
    'WeeklyReviewView rendering should live in a dedicated content module',
  );
  assert.match(
    contentSource,
    /import DeferredTaskRow from '\.\/content\/DeferredTaskRow';/,
    'WeeklyReviewContent should delegate deferred task rendering to a dedicated content submodule',
  );
  assert.match(
    contentSource,
    /import StalledListRow from '\.\/content\/StalledListRow';/,
    'WeeklyReviewContent should delegate stalled list rendering to a dedicated content submodule',
  );
  assert.match(statCardSource, /export default function StatCard/);
  assert.match(reviewSectionSource, /export default function ReviewSection/);
  assert.match(stalledProjectRowSource, /export default function StalledListRow/);
  assert.match(deferredTaskRowSource, /export default function DeferredTaskRow/);
});
