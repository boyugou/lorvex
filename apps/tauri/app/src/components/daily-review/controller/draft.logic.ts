import { isCanonicalYmd } from '@/lib/dayContextMath';
import { tryParseJson } from '@/lib/security/jsonParse';
import { hasOnlyKeys, isPlainRecord as isRecord } from '@/lib/objectGuards';
import { DRAFT_KEYS } from '@/lib/storage/drafts';

export const DAILY_REVIEW_DRAFT_STORAGE_KEY = DRAFT_KEYS.dailyReview;

export interface DailyReviewDraft {
  summary: string;
  mood: number | null;
  energy: number | null;
  wins: string;
  blockers: string;
  learnings: string;
}

export interface PersistedDailyReviewDraft extends DailyReviewDraft {
  expectedDate: string;
}

const DAILY_REVIEW_DRAFT_KEYS = new Set([
  'blockers',
  'energy',
  'expectedDate',
  'learnings',
  'mood',
  'summary',
  'wins',
]);

function readRating(value: unknown): number | null | undefined {
  if (value === null) return null;
  if (typeof value !== 'number' || !Number.isInteger(value)) return undefined;
  return value >= 1 && value <= 5 ? value : undefined;
}

function hasOnlyDailyReviewDraftKeys(value: Record<string, unknown>): boolean {
  return hasOnlyKeys(value, DAILY_REVIEW_DRAFT_KEYS);
}

export function parseDailyReviewDraftStorageValue(raw: string | null): PersistedDailyReviewDraft | null {
  if (!raw) return null;
  const parsed = tryParseJson(raw);
  if (!parsed.ok || !isRecord(parsed.value) || !hasOnlyDailyReviewDraftKeys(parsed.value)) {
    return null;
  }
  const draft = parsed.value;
  const mood = readRating(draft.mood);
  const energy = readRating(draft.energy);
  if (
    !isCanonicalYmd(draft.expectedDate)
    || typeof draft.summary !== 'string'
    || mood === undefined
    || energy === undefined
    || typeof draft.wins !== 'string'
    || typeof draft.blockers !== 'string'
    || typeof draft.learnings !== 'string'
  ) {
    return null;
  }
  return {
    expectedDate: draft.expectedDate,
    summary: draft.summary,
    mood,
    energy,
    wins: draft.wins,
    blockers: draft.blockers,
    learnings: draft.learnings,
  };
}

export function readDailyReviewDraftFromStorage(readRaw: () => string | null): PersistedDailyReviewDraft | null {
  try {
    return parseDailyReviewDraftStorageValue(readRaw());
  } catch {
    return null;
  }
}

export function serializeDailyReviewDraft(draft: PersistedDailyReviewDraft): string {
  return JSON.stringify(draft);
}
