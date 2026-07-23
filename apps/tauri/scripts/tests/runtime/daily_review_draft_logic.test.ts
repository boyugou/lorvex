import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DAILY_REVIEW_DRAFT_STORAGE_KEY,
  parseDailyReviewDraftStorageValue,
  readDailyReviewDraftFromStorage,
  serializeDailyReviewDraft,
} from '../../../app/src/components/daily-review/controller/draft.logic';

test('daily review draft parser restores only well-formed payloads', () => {
  assert.deepEqual(
    parseDailyReviewDraftStorageValue('{"summary":"Good day","mood":4,"energy":3,"wins":"ship","blockers":"none","learnings":"rest"}'),
    null,
  );
  assert.deepEqual(
    parseDailyReviewDraftStorageValue('{"expectedDate":"2026-04-20","summary":"Good day","mood":4,"energy":3,"wins":"ship","blockers":"none","learnings":"rest"}'),
    {
      expectedDate: '2026-04-20',
      summary: 'Good day',
      mood: 4,
      energy: 3,
      wins: 'ship',
      blockers: 'none',
      learnings: 'rest',
    },
  );
  assert.equal(parseDailyReviewDraftStorageValue('{"mood":4}'), null);
  assert.equal(parseDailyReviewDraftStorageValue('{oops'), null);
  assert.equal(
    parseDailyReviewDraftStorageValue('{"expectedDate":"tomorrow","summary":"Good day","mood":4,"energy":3,"wins":"ship","blockers":"none","learnings":"rest"}'),
    null,
  );
  assert.equal(
    parseDailyReviewDraftStorageValue('{"expectedDate":"2026-04-20","summary":"Good day","mood":6,"energy":3,"wins":"ship","blockers":"none","learnings":"rest"}'),
    null,
  );
  assert.equal(
    parseDailyReviewDraftStorageValue('{"expectedDate":"2026-04-20","summary":"Good day","mood":4,"energy":3.5,"wins":"ship","blockers":"none","learnings":"rest"}'),
    null,
  );
  assert.equal(
    parseDailyReviewDraftStorageValue('{"expectedDate":"2026-04-20","summary":"Good day","mood":4,"energy":3,"wins":"ship","blockers":"none","learnings":"rest","debug":true}'),
    null,
  );
});

test('daily review draft serializer round-trips with the parser', () => {
  const serialized = serializeDailyReviewDraft({
    expectedDate: '2026-04-20',
    summary: 'Focus',
    mood: null,
    energy: 5,
    wins: '',
    blockers: '',
    learnings: 'hydrate',
  });
  assert.deepEqual(parseDailyReviewDraftStorageValue(serialized), {
    expectedDate: '2026-04-20',
    summary: 'Focus',
    mood: null,
    energy: 5,
    wins: '',
    blockers: '',
    learnings: 'hydrate',
  });
});

test('daily review draft storage uses a single canonical key while preserving the composed date in payload', () => {
  assert.equal(DAILY_REVIEW_DRAFT_STORAGE_KEY, 'lorvex.dailyReview.draft');
  const serialized = serializeDailyReviewDraft({
    expectedDate: '2026-04-20',
    summary: 'Late entry',
    mood: 3,
    energy: 2,
    wins: '',
    blockers: '',
    learnings: '',
  });
  assert.deepEqual(parseDailyReviewDraftStorageValue(serialized), {
    expectedDate: '2026-04-20',
    summary: 'Late entry',
    mood: 3,
    energy: 2,
    wins: '',
    blockers: '',
    learnings: '',
  });
});

test('daily review draft storage reader fails closed when storage access throws', () => {
  assert.equal(readDailyReviewDraftFromStorage(() => {
    throw new Error('storage unavailable');
  }), null);
});
