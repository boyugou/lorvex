import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildDailyReviewDraftPayload,
  buildDailyReviewReflectionExpandedSections,
  buildDailyReviewReflectionExpansionState,
  buildDailyReviewUnmountPersistence,
  buildDailyReviewUpsertInput,
  reconcileDailyReviewReflectionExpansionState,
  hasDailyReviewDraftContent,
  resolveDailyReviewInitialState,
  shouldResetDailyReviewComposedDate,
  toggleDailyReviewReflectionSection,
} from '../../../app/src/components/daily-review/controller/controller.logic';

test('daily review initialization restores a persisted draft before the fetched remote copy', () => {
  const initial = resolveDailyReviewInitialState({
    initialized: false,
    dirty: false,
    todayReviewLoaded: true,
    storedDraft: {
      expectedDate: '2026-04-20',
      summary: 'Late draft',
      mood: 4,
      energy: 3,
      wins: 'ship',
      blockers: '',
      learnings: '',
    },
    todayReview: {
      id: 'review-1',
      date: '2026-04-21',
      summary: 'Remote copy',
      mood: 1,
      energy_level: 1,
      wins: null,
      blockers: null,
      learnings: null,
      ai_synthesis: null,
      created_at: '2026-04-21T00:00:00Z',
      updated_at: '2026-04-21T00:00:00Z',
    },
    todayYmd: '2026-04-21',
  });

  assert.deepEqual(initial, {
    source: 'draft',
    form: {
      expectedDate: '2026-04-20',
      summary: 'Late draft',
      mood: 4,
      energy: 3,
      wins: 'ship',
      blockers: '',
      learnings: '',
    },
  });
});

test('daily review initialization marks a blank-but-loaded day as initialized with empty form state', () => {
  const initial = resolveDailyReviewInitialState({
    initialized: false,
    dirty: false,
    todayReviewLoaded: true,
    storedDraft: null,
    todayReview: null,
    todayYmd: '2026-04-21',
  });

  assert.deepEqual(initial, {
    source: 'blank',
    form: {
      expectedDate: '2026-04-21',
      summary: '',
      mood: null,
      energy: null,
      wins: '',
      blockers: '',
      learnings: '',
    },
  });
});

test('daily review initialization stays inert until the today-review query has resolved', () => {
  assert.equal(resolveDailyReviewInitialState({
    initialized: false,
    dirty: false,
    todayReviewLoaded: false,
    storedDraft: {
      expectedDate: '2026-04-20',
      summary: 'draft',
      mood: null,
      energy: null,
      wins: '',
      blockers: '',
      learnings: '',
    },
    todayReview: null,
    todayYmd: '2026-04-21',
  }), null);
});

test('daily review reflection expansion defaults expand only empty optional sections', () => {
  assert.deepEqual(buildDailyReviewReflectionExpandedSections({
    wins: 'Shipped',
    blockers: '',
    learnings: '  ',
  }), {
    wins: false,
    blockers: true,
    learnings: true,
  });
});

test('daily review reflection expansion is scoped by date and hydration revision', () => {
  const previous = buildDailyReviewReflectionExpansionState({
    scopeDate: '2026-04-21',
    hydrationRevision: 1,
    wins: '',
    blockers: '',
    learnings: '',
  });
  const userToggled = {
    ...previous,
    sections: { ...previous.sections, wins: false },
  };

  assert.equal(reconcileDailyReviewReflectionExpansionState(userToggled, buildDailyReviewReflectionExpansionState({
    scopeDate: '2026-04-21',
    hydrationRevision: 1,
    wins: 'Async edit on same scope must not clobber toggles',
    blockers: '',
    learnings: '',
  })), userToggled);

  assert.deepEqual(reconcileDailyReviewReflectionExpansionState(userToggled, buildDailyReviewReflectionExpansionState({
    scopeDate: '2026-04-21',
    hydrationRevision: 2,
    wins: 'Hydrated win',
    blockers: '',
    learnings: 'Hydrated learning',
  })), {
    scopeDate: '2026-04-21',
    hydrationRevision: 2,
    sections: {
      wins: false,
      blockers: true,
      learnings: false,
    },
  });

  assert.deepEqual(reconcileDailyReviewReflectionExpansionState(userToggled, buildDailyReviewReflectionExpansionState({
    scopeDate: '2026-04-22',
    hydrationRevision: 2,
    wins: 'Loaded win',
    blockers: '',
    learnings: '',
  })), {
    scopeDate: '2026-04-22',
    hydrationRevision: 2,
    sections: {
      wins: false,
      blockers: true,
      learnings: true,
    },
  });
});

test('daily review reflection expansion state-machine preserves toggles across same-scope rerenders', () => {
  let state = buildDailyReviewReflectionExpansionState({
    scopeDate: '2026-04-21',
    hydrationRevision: 1,
    wins: '',
    blockers: '',
    learnings: '',
  });

  state = toggleDailyReviewReflectionSection(state, 'wins');
  assert.equal(state.sections.wins, false);

  state = reconcileDailyReviewReflectionExpansionState(state, buildDailyReviewReflectionExpansionState({
    scopeDate: '2026-04-21',
    hydrationRevision: 1,
    wins: 'User typed after toggling',
    blockers: '',
    learnings: '',
  }));
  assert.equal(
    state.sections.wins,
    false,
    'same-date field edits must not clobber a manual collapse',
  );

  state = reconcileDailyReviewReflectionExpansionState(state, buildDailyReviewReflectionExpansionState({
    scopeDate: '2026-04-21',
    hydrationRevision: 2,
    wins: 'Hydrated remote value',
    blockers: '',
    learnings: '',
  }));
  assert.deepEqual(
    state.sections,
    { wins: false, blockers: true, learnings: true },
    'hydration revision changes own a fresh default expansion pass',
  );

  state = toggleDailyReviewReflectionSection(state, 'blockers');
  assert.equal(state.sections.blockers, false);

  state = reconcileDailyReviewReflectionExpansionState(state, buildDailyReviewReflectionExpansionState({
    scopeDate: '2026-04-22',
    hydrationRevision: 3,
    wins: '',
    blockers: '',
    learnings: 'New day learning',
  }));
  assert.deepEqual(
    state.sections,
    { wins: true, blockers: true, learnings: false },
    'date changes must drop stale toggles from the previous review day',
  );
});

test('daily review draft payload trims summary and preserves the composed date across midnight remounts', () => {
  assert.deepEqual(buildDailyReviewDraftPayload({
    summary: '  Late entry  ',
    mood: 3,
    energy: 2,
    wins: 'kept writing',
    blockers: '',
    learnings: '',
    composedForDate: '2026-04-20',
    todayYmd: '2026-04-21',
  }), {
    expectedDate: '2026-04-20',
    summary: 'Late entry',
    mood: 3,
    energy: 2,
    wins: 'kept writing',
    blockers: '',
    learnings: '',
  });
});

test('daily review draft payload persists partial input even before the summary is filled', () => {
  assert.equal(hasDailyReviewDraftContent({
    summary: '   ',
    mood: 4,
    energy: null,
    wins: '',
    blockers: '',
    learnings: '',
  }), true);

  assert.deepEqual(buildDailyReviewDraftPayload({
    summary: '   ',
    mood: 4,
    energy: null,
    wins: '',
    blockers: 'found one',
    learnings: '',
    composedForDate: null,
    todayYmd: '2026-04-21',
  }), {
    expectedDate: '2026-04-21',
    summary: '',
    mood: 4,
    energy: null,
    wins: '',
    blockers: 'found one',
    learnings: '',
  });
});

test('daily review upsert input fails closed on blank summaries and normalizes optional text fields', () => {
  assert.equal(buildDailyReviewUpsertInput({
    summary: '   ',
    mood: null,
    energy: null,
    wins: '',
    blockers: '',
    learnings: '',
    composedForDate: null,
    todayYmd: '2026-04-21',
  }), null);

  assert.deepEqual(buildDailyReviewUpsertInput({
    summary: '  Focus  ',
    mood: 4,
    energy: 5,
    wins: '  shipped  ',
    blockers: '  ',
    learnings: ' hydrate ',
    composedForDate: null,
    todayYmd: '2026-04-21',
  }), {
    summary: 'Focus',
    mood: 4,
    energy_level: 5,
    wins: 'shipped',
    blockers: null,
    learnings: 'hydrate',
    expected_date: '2026-04-21',
  });
});

test('daily review composed date resets only when a clean session is pinned to a different day', () => {
  assert.equal(shouldResetDailyReviewComposedDate({
    composedForDate: '2026-04-20',
    dirty: false,
    todayYmd: '2026-04-21',
  }), true);

  assert.equal(shouldResetDailyReviewComposedDate({
    composedForDate: '2026-04-20',
    dirty: true,
    todayYmd: '2026-04-21',
  }), false);

  assert.equal(shouldResetDailyReviewComposedDate({
    composedForDate: null,
    dirty: false,
    todayYmd: '2026-04-21',
  }), false);
});

test('daily review unmount persistence keeps a durable partial draft even when no upsert is possible yet', () => {
  assert.deepEqual(buildDailyReviewUnmountPersistence({
    summary: '   ',
    mood: null,
    energy: 5,
    wins: '',
    blockers: 'waiting on approval',
    learnings: '',
    composedForDate: '2026-04-20',
    todayYmd: '2026-04-21',
  }), {
    draft: {
      expectedDate: '2026-04-20',
      summary: '',
      mood: null,
      energy: 5,
      wins: '',
      blockers: 'waiting on approval',
      learnings: '',
    },
    upsertInput: null,
  });
});
