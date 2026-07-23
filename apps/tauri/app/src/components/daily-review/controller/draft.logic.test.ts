import { describe, expect, test } from 'vitest';

import {
  parseDailyReviewDraftStorageValue,
  readDailyReviewDraftFromStorage,
  serializeDailyReviewDraft,
  type PersistedDailyReviewDraft,
} from './draft.logic';

// `parseDailyReviewDraftStorageValue` is the trust boundary between
// localStorage (which can hold anything — corrupted JSON, schema drift
// from a downgrade, a different app's keys colliding) and the daily
// review draft state. A regression that silently lets a malformed
// payload through would corrupt the form on next mount; a regression
// that's too strict would discard the user's in-progress draft on every
// save. These cases pin the contract: only round-tripped, well-typed,
// canonical-date payloads survive.

const VALID_DRAFT: PersistedDailyReviewDraft = {
  expectedDate: '2026-05-03',
  summary: 'shipped the feature',
  mood: 4,
  energy: 3,
  wins: 'tests added',
  blockers: 'CI flake',
  learnings: 'sanitize early',
};

describe('parseDailyReviewDraftStorageValue', () => {
  test('returns null on empty / null input (cold start)', () => {
    expect(parseDailyReviewDraftStorageValue(null)).toBeNull();
    expect(parseDailyReviewDraftStorageValue('')).toBeNull();
  });

  test('returns null on non-JSON garbage', () => {
    expect(parseDailyReviewDraftStorageValue('not json')).toBeNull();
    expect(parseDailyReviewDraftStorageValue('{bad')).toBeNull();
  });

  test('returns null on non-object root (array, scalar)', () => {
    expect(parseDailyReviewDraftStorageValue('[]')).toBeNull();
    expect(parseDailyReviewDraftStorageValue('"draft"')).toBeNull();
    expect(parseDailyReviewDraftStorageValue('42')).toBeNull();
    expect(parseDailyReviewDraftStorageValue('null')).toBeNull();
  });

  test('returns null when an unknown key sneaks in (refusing schema drift)', () => {
    const withExtra = { ...VALID_DRAFT, extraneous: true };
    expect(parseDailyReviewDraftStorageValue(JSON.stringify(withExtra))).toBeNull();
  });

  test('round-trips a fully-valid draft (every field type-checked)', () => {
    const round = parseDailyReviewDraftStorageValue(JSON.stringify(VALID_DRAFT));
    expect(round).toEqual(VALID_DRAFT);
  });

  test('preserves null mood / energy (user can clear ratings)', () => {
    const partial = { ...VALID_DRAFT, mood: null, energy: null };
    expect(parseDailyReviewDraftStorageValue(JSON.stringify(partial))).toEqual(partial);
  });

  test('rejects non-canonical date (wrong shape, real-but-malformed, future-month-day)', () => {
    expect(
      parseDailyReviewDraftStorageValue(JSON.stringify({ ...VALID_DRAFT, expectedDate: '2026-5-3' })),
    ).toBeNull();
    expect(
      parseDailyReviewDraftStorageValue(JSON.stringify({ ...VALID_DRAFT, expectedDate: '2026-13-01' })),
    ).toBeNull();
    expect(
      parseDailyReviewDraftStorageValue(JSON.stringify({ ...VALID_DRAFT, expectedDate: '2026-02-30' })),
    ).toBeNull();
    expect(
      parseDailyReviewDraftStorageValue(JSON.stringify({ ...VALID_DRAFT, expectedDate: 'today' })),
    ).toBeNull();
  });

  test('rejects out-of-range mood (must be 1-5 integer or null)', () => {
    for (const bad of [0, 6, 1.5, -1, 'three']) {
      expect(
        parseDailyReviewDraftStorageValue(
          JSON.stringify({ ...VALID_DRAFT, mood: bad as unknown as number }),
        ),
      ).toBeNull();
    }
  });

  test('rejects when summary / wins / blockers / learnings are non-string', () => {
    for (const field of ['summary', 'wins', 'blockers', 'learnings'] as const) {
      const bad = { ...VALID_DRAFT, [field]: 42 } as unknown as PersistedDailyReviewDraft;
      expect(parseDailyReviewDraftStorageValue(JSON.stringify(bad))).toBeNull();
    }
  });

  test('accepts empty strings (a draft with only ratings is valid)', () => {
    const sparse: PersistedDailyReviewDraft = {
      expectedDate: '2026-05-03',
      summary: '',
      mood: 3,
      energy: 3,
      wins: '',
      blockers: '',
      learnings: '',
    };
    expect(parseDailyReviewDraftStorageValue(JSON.stringify(sparse))).toEqual(sparse);
  });
});

describe('readDailyReviewDraftFromStorage', () => {
  test('returns null when the reader throws (storage unavailable / quota exceeded)', () => {
    const draft = readDailyReviewDraftFromStorage(() => {
      throw new Error('quota exceeded');
    });
    expect(draft).toBeNull();
  });

  test('round-trips through a custom reader', () => {
    const reader = () => JSON.stringify(VALID_DRAFT);
    expect(readDailyReviewDraftFromStorage(reader)).toEqual(VALID_DRAFT);
  });
});

describe('serializeDailyReviewDraft', () => {
  test('produces JSON that round-trips back through parse', () => {
    const serialized = serializeDailyReviewDraft(VALID_DRAFT);
    expect(parseDailyReviewDraftStorageValue(serialized)).toEqual(VALID_DRAFT);
  });
});
