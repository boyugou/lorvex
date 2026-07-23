import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function read(relPath) {
  return fs.readFileSync(path.join(repoRoot, relPath), 'utf8');
}

test('Daily Review mood and energy scale metadata has one frontend source of truth', () => {
  const rootView = read('app/src/components/DailyReviewView.tsx');
  const moodEnergySection = read('app/src/components/daily-review/content/MoodEnergySection.tsx');
  const controller = read('app/src/components/daily-review/controller/useDailyReviewController.ts');
  const reviewCard = read('app/src/components/daily-review/content/ReviewCard.tsx');
  const scaleMetadata = read('app/src/components/daily-review/controller/scaleMetadata.logic.ts');

  assert.match(scaleMetadata, /export const DAILY_REVIEW_SCALE_VALUES = \[1, 2, 3, 4, 5\] as const/);
  assert.match(scaleMetadata, /export const DAILY_REVIEW_MOOD_SCALE/);
  assert.match(scaleMetadata, /export const DAILY_REVIEW_ENERGY_SCALE/);
  assert.match(scaleMetadata, /export function formatDailyReviewScaleCopyParts/);
  assert.match(scaleMetadata, /export function formatDailyReviewScaleTooltipLabel/);

  assert.match(moodEnergySection, /DAILY_REVIEW_MOOD_SCALE/);
  assert.match(moodEnergySection, /DAILY_REVIEW_ENERGY_SCALE/);
  assert.match(moodEnergySection, /formatDailyReviewScaleAriaLabel/);
  assert.doesNotMatch(rootView, /DAILY_REVIEW_(?:MOOD|ENERGY)_SCALE/);
  assert.match(controller, /formatDailyReviewScaleCopyParts/);
  assert.match(reviewCard, /getDailyReviewScaleOption/);
  assert.match(reviewCard, /formatDailyReviewScaleTooltipLabel/);

  const duplicateMetadataPattern = /const\s+(?:MOOD_ICONS|ENERGY_ICONS|MOOD_ICONS_DISPLAY|ENERGY_LEVELS)\b/;
  assert.doesNotMatch(rootView, duplicateMetadataPattern);
  assert.doesNotMatch(moodEnergySection, duplicateMetadataPattern);
  assert.doesNotMatch(controller, duplicateMetadataPattern);
  assert.doesNotMatch(reviewCard, duplicateMetadataPattern);
});
