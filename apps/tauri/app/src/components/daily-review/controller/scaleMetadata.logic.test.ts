import { describe, expect, it } from 'vitest';

import type { TranslationKey } from '@/lib/i18n';
import {
  DAILY_REVIEW_ENERGY_SCALE,
  DAILY_REVIEW_MOOD_SCALE,
  DAILY_REVIEW_SCALE_VALUES,
  formatDailyReviewScaleAriaLabel,
  formatDailyReviewScaleCopyParts,
  formatDailyReviewScaleTooltipLabel,
  formatDailyReviewScaleValue,
  getDailyReviewScaleOption,
} from './scaleMetadata.logic';

const t = (key: TranslationKey) => key;

describe('daily review scale metadata', () => {
  it('covers every 1-5 scale value for mood and energy', () => {
    expect(DAILY_REVIEW_MOOD_SCALE.map((option) => option.value)).toEqual(DAILY_REVIEW_SCALE_VALUES);
    expect(DAILY_REVIEW_ENERGY_SCALE.map((option) => option.value)).toEqual(DAILY_REVIEW_SCALE_VALUES);
    for (const value of DAILY_REVIEW_SCALE_VALUES) {
      expect(getDailyReviewScaleOption('mood', value)?.icon).toBeTruthy();
      expect(getDailyReviewScaleOption('energy', value)?.icon).toBeTruthy();
      expect(getDailyReviewScaleOption('energy', value)?.labelKey).toMatch(/^dailyReview\./);
    }
  });

  it('formats selector aria labels from the shared metadata', () => {
    expect(formatDailyReviewScaleAriaLabel({
      kind: 'mood',
      locale: 'en-US',
      t,
      value: 4,
    })).toBe('dailyReview.mood 4/5');
    expect(formatDailyReviewScaleAriaLabel({
      kind: 'energy',
      locale: 'en-US',
      t,
      value: 5,
    })).toBe('dailyReview.energy 5/5 dailyReview.energized');
  });

  it('formats copy and historical-card labels from the same value helper', () => {
    expect(formatDailyReviewScaleValue('mood', 1, 'en-US')).toBe('\u{1F61E} 1/5');
    expect(formatDailyReviewScaleTooltipLabel({
      kind: 'energy',
      value: 3,
      locale: 'en-US',
      t,
    })).toBe('dailyReview.energy: \u26A1 3/5');
    expect(formatDailyReviewScaleCopyParts({
      mood: 5,
      energyLevel: 1,
      locale: 'en-US',
      t,
    })).toEqual([
      'dailyReview.mood: \u{1F604} 5/5',
      'dailyReview.energy: \u{1F4A4} 1/5',
    ]);
  });

  it('drops invalid persisted values instead of rendering blank icon shells', () => {
    expect(getDailyReviewScaleOption('mood', 0)).toBeNull();
    expect(formatDailyReviewScaleValue('energy', 6, 'en-US')).toBeNull();
    expect(formatDailyReviewScaleCopyParts({
      mood: 9,
      energyLevel: null,
      locale: 'en-US',
      t,
    })).toEqual([]);
  });
});
