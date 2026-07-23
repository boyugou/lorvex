import type { DailyReview } from '@/lib/ipc/tasks/models';
import type { DailyReviewDraft, PersistedDailyReviewDraft } from './draft.logic';

interface DailyReviewFormState extends DailyReviewDraft {
  expectedDate: string;
}

export type DailyReviewReflectionSectionKey = 'wins' | 'blockers' | 'learnings';

type DailyReviewReflectionExpandedSections = Record<DailyReviewReflectionSectionKey, boolean>;

interface DailyReviewReflectionExpansionState {
  scopeDate: string;
  hydrationRevision: number;
  sections: DailyReviewReflectionExpandedSections;
}

interface ResolveDailyReviewInitialStateInput {
  initialized: boolean;
  dirty: boolean;
  todayReviewLoaded: boolean;
  storedDraft: PersistedDailyReviewDraft | null;
  todayReview: DailyReview | null;
  todayYmd: string;
}

interface ResolvedDailyReviewInitialState {
  source: 'draft' | 'review' | 'blank';
  form: DailyReviewFormState;
}

export function resolveDailyReviewInitialState(
  input: ResolveDailyReviewInitialStateInput,
): ResolvedDailyReviewInitialState | null {
  if (input.initialized || input.dirty || !input.todayReviewLoaded) return null;

  if (input.storedDraft) {
    return {
      source: 'draft',
      form: input.storedDraft,
    };
  }

  if (input.todayReview) {
    return {
      source: 'review',
      form: {
        expectedDate: input.todayYmd,
        summary: input.todayReview.summary,
        mood: input.todayReview.mood,
        energy: input.todayReview.energy_level,
        wins: input.todayReview.wins ?? '',
        blockers: input.todayReview.blockers ?? '',
        learnings: input.todayReview.learnings ?? '',
      },
    };
  }

  return {
    source: 'blank',
    form: {
      expectedDate: input.todayYmd,
      summary: '',
      mood: null,
      energy: null,
      wins: '',
      blockers: '',
      learnings: '',
    },
  };
}

export function buildDailyReviewReflectionExpandedSections(input: {
  wins: string;
  blockers: string;
  learnings: string;
}): DailyReviewReflectionExpandedSections {
  return {
    wins: input.wins.trim().length === 0,
    blockers: input.blockers.trim().length === 0,
    learnings: input.learnings.trim().length === 0,
  };
}

export function buildDailyReviewReflectionExpansionState(input: {
  scopeDate: string;
  hydrationRevision: number;
  wins: string;
  blockers: string;
  learnings: string;
}): DailyReviewReflectionExpansionState {
  return {
    scopeDate: input.scopeDate,
    hydrationRevision: input.hydrationRevision,
    sections: buildDailyReviewReflectionExpandedSections(input),
  };
}

export function reconcileDailyReviewReflectionExpansionState(
  previous: DailyReviewReflectionExpansionState,
  next: DailyReviewReflectionExpansionState,
): DailyReviewReflectionExpansionState {
  if (
    previous.scopeDate === next.scopeDate
    && previous.hydrationRevision === next.hydrationRevision
  ) {
    return previous;
  }

  return next;
}

export function toggleDailyReviewReflectionSection(
  previous: DailyReviewReflectionExpansionState,
  key: DailyReviewReflectionSectionKey,
): DailyReviewReflectionExpansionState {
  return {
    ...previous,
    sections: {
      ...previous.sections,
      [key]: !previous.sections[key],
    },
  };
}

interface BuildDailyReviewDraftPayloadInput extends DailyReviewDraft {
  composedForDate: string | null;
  todayYmd: string;
}

export function hasDailyReviewDraftContent(input: DailyReviewDraft): boolean {
  return (
    input.summary.trim().length > 0
    || input.mood !== null
    || input.energy !== null
    || input.wins.trim().length > 0
    || input.blockers.trim().length > 0
    || input.learnings.trim().length > 0
  );
}

export function buildDailyReviewDraftPayload(
  input: BuildDailyReviewDraftPayloadInput,
): PersistedDailyReviewDraft | null {
  if (!hasDailyReviewDraftContent(input)) return null;
  return {
    expectedDate: input.composedForDate ?? input.todayYmd,
    summary: input.summary.trim(),
    mood: input.mood,
    energy: input.energy,
    wins: input.wins,
    blockers: input.blockers,
    learnings: input.learnings,
  };
}

export function buildDailyReviewUpsertInput(input: BuildDailyReviewDraftPayloadInput) {
  const draft = buildDailyReviewDraftPayload(input);
  if (!draft || draft.summary.length === 0) return null;
  return {
    summary: draft.summary,
    mood: draft.mood,
    energy_level: draft.energy,
    wins: draft.wins.trim() || null,
    blockers: draft.blockers.trim() || null,
    learnings: draft.learnings.trim() || null,
    expected_date: draft.expectedDate,
  };
}

export function buildDailyReviewUnmountPersistence(input: BuildDailyReviewDraftPayloadInput): {
  draft: PersistedDailyReviewDraft | null;
  upsertInput: ReturnType<typeof buildDailyReviewUpsertInput>;
} {
  const draft = buildDailyReviewDraftPayload(input);
  return {
    draft,
    upsertInput: draft && draft.summary.length > 0
      ? {
          summary: draft.summary,
          mood: draft.mood,
          energy_level: draft.energy,
          wins: draft.wins.trim() || null,
          blockers: draft.blockers.trim() || null,
          learnings: draft.learnings.trim() || null,
          expected_date: draft.expectedDate,
        }
      : null,
  };
}

export function shouldResetDailyReviewComposedDate(args: {
  composedForDate: string | null;
  dirty: boolean;
  todayYmd: string;
}): boolean {
  return !args.dirty && args.composedForDate !== null && args.composedForDate !== args.todayYmd;
}
