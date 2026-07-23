import { describe, it, expect } from 'vitest';

import {
  ONBOARDING_STEP_META,
  ONBOARDING_STEPS,
  buildPreviouslyDoneState,
  computeOnboardingProgress,
  parsePreviouslyDoneState,
  serializePreviouslyDoneState,
  shouldShowOnboardingChecklist,
  type OnboardingSignals,
} from './onboardingProgress.logic';
import { buildSettingsSectionIds } from '../settingsView.runtime';

const FRESH_INSTALL: OnboardingSignals = {
  mcpResolved: false,
  syncBackendKind: null,
  hasAnyTask: false,
  notificationsGranted: false,
};

const ALL_GOOD: OnboardingSignals = {
  mcpResolved: true,
  syncBackendKind: 'filesystem_bridge',
  hasAnyTask: true,
  notificationsGranted: true,
};

describe('computeOnboardingProgress', () => {
  it('reports zero done on a fresh install', () => {
    const progress = computeOnboardingProgress(FRESH_INSTALL);
    expect(progress.completed).toBe(0);
    expect(progress.total).toBe(ONBOARDING_STEPS.length);
    expect(progress.allDone).toBe(false);
    expect(progress.hasRegression).toBe(false);
    for (const step of progress.steps) {
      expect(step.done).toBe(false);
      expect(step.regressed).toBe(false);
    }
  });

  it('reports all done when every signal is satisfied', () => {
    const progress = computeOnboardingProgress(ALL_GOOD);
    expect(progress.completed).toBe(ONBOARDING_STEPS.length);
    expect(progress.allDone).toBe(true);
    expect(progress.hasRegression).toBe(false);
    for (const step of progress.steps) {
      expect(step.done).toBe(true);
    }
  });

  it('treats null mcpResolved (unsupported runtime) as not-done', () => {
    const progress = computeOnboardingProgress({ ...ALL_GOOD, mcpResolved: null });
    const mcp = progress.steps.find((s) => s.id === 'mcp');
    expect(mcp?.done).toBe(false);
    expect(progress.allDone).toBe(false);
  });

  it('treats empty string syncBackendKind as not configured', () => {
    const progress = computeOnboardingProgress({ ...FRESH_INSTALL, syncBackendKind: '   ' });
    const sync = progress.steps.find((s) => s.id === 'sync');
    expect(sync?.done).toBe(false);
  });

  it('marks a step as regressed when previously done but now not done', () => {
    // sync was on, now off
    const previouslyDone = new Set<typeof ONBOARDING_STEPS[number]>(['mcp', 'sync', 'firstTask']);
    const progress = computeOnboardingProgress(
      { ...FRESH_INSTALL, mcpResolved: true, hasAnyTask: true },
      previouslyDone,
    );
    const sync = progress.steps.find((s) => s.id === 'sync');
    expect(sync?.done).toBe(false);
    expect(sync?.regressed).toBe(true);
    expect(progress.hasRegression).toBe(true);
  });

  it('does not mark a step regressed if it is currently done', () => {
    const previouslyDone = new Set<typeof ONBOARDING_STEPS[number]>(['mcp']);
    const progress = computeOnboardingProgress(ALL_GOOD, previouslyDone);
    const mcp = progress.steps.find((s) => s.id === 'mcp');
    expect(mcp?.regressed).toBe(false);
  });
});

describe('shouldShowOnboardingChecklist', () => {
  it('shows when not dismissed and not all done', () => {
    const progress = computeOnboardingProgress(FRESH_INSTALL);
    expect(shouldShowOnboardingChecklist(progress, false)).toBe(true);
  });

  it('hides when dismissed and not all done and no regression', () => {
    const progress = computeOnboardingProgress(FRESH_INSTALL);
    expect(shouldShowOnboardingChecklist(progress, true)).toBe(false);
  });

  it('hides when all done even if not dismissed', () => {
    const progress = computeOnboardingProgress(ALL_GOOD);
    expect(shouldShowOnboardingChecklist(progress, false)).toBe(false);
  });

  it('re-surfaces when a step regressed even if previously dismissed', () => {
    const previouslyDone = new Set<typeof ONBOARDING_STEPS[number]>(['mcp', 'sync']);
    const progress = computeOnboardingProgress(
      { ...FRESH_INSTALL, mcpResolved: true },
      previouslyDone,
    );
    expect(progress.hasRegression).toBe(true);
    expect(shouldShowOnboardingChecklist(progress, true)).toBe(true);
  });
});

describe('parsePreviouslyDoneState / serializePreviouslyDoneState', () => {
  it('builds cumulative previously-done state in stable step order', () => {
    const progress = computeOnboardingProgress({
      ...FRESH_INSTALL,
      mcpResolved: true,
    });
    const previouslyDone = new Set<typeof ONBOARDING_STEPS[number]>(['sync', 'firstTask']);

    expect(buildPreviouslyDoneState(progress, previouslyDone)).toEqual([
      'mcp',
      'sync',
      'firstTask',
    ]);
  });

  it('round-trips a non-empty done set', () => {
    const progress = computeOnboardingProgress(ALL_GOOD);
    const serialized = serializePreviouslyDoneState(progress);
    const parsed = parsePreviouslyDoneState(serialized);
    expect(parsed.size).toBe(ONBOARDING_STEPS.length);
    for (const step of ONBOARDING_STEPS) {
      expect(parsed.has(step)).toBe(true);
    }
  });

  it('returns empty set for null input', () => {
    expect(parsePreviouslyDoneState(null).size).toBe(0);
  });

  it('returns empty set for malformed JSON', () => {
    expect(parsePreviouslyDoneState('not-json').size).toBe(0);
    expect(parsePreviouslyDoneState('{}').size).toBe(0);
    expect(parsePreviouslyDoneState('null').size).toBe(0);
  });

  it('skips unknown step ids', () => {
    const parsed = parsePreviouslyDoneState(JSON.stringify(['mcp', 'invalid', 'sync']));
    expect(parsed.size).toBe(2);
    expect(parsed.has('mcp')).toBe(true);
    expect(parsed.has('sync')).toBe(true);
  });

  it('serializes a partially-done progress in stable order', () => {
    const progress = computeOnboardingProgress({
      ...FRESH_INSTALL,
      mcpResolved: true,
      hasAnyTask: true,
    });
    const serialized = serializePreviouslyDoneState(progress);
    expect(JSON.parse(serialized)).toEqual(['mcp', 'firstTask']);
  });

  it('serializes a cumulative set when previously-done steps later regress', () => {
    const progress = computeOnboardingProgress({
      ...FRESH_INSTALL,
      mcpResolved: true,
    });
    const serialized = serializePreviouslyDoneState(
      progress,
      new Set<typeof ONBOARDING_STEPS[number]>(['sync', 'firstTask']),
    );
    expect(JSON.parse(serialized)).toEqual(['mcp', 'sync', 'firstTask']);
  });

  it('serializes empty when nothing done', () => {
    const progress = computeOnboardingProgress(FRESH_INSTALL);
    expect(serializePreviouslyDoneState(progress)).toBe('[]');
  });
});

describe('onboarding settings targets', () => {
  it('points the notifications step at a registered settings section', () => {
    const action = ONBOARDING_STEP_META.notifications.action;
    expect(action.kind).toBe('settings');
    if (action.kind !== 'settings') return;

    expect(
      buildSettingsSectionIds({
        hasSyncBackends: true,
        supportsMcpHosting: true,
      }),
    ).toContain(action.sectionId);
  });
});
