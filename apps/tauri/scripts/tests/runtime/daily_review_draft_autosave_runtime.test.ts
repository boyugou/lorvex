import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import type { PersistedDailyReviewDraft } from '../../../app/src/components/daily-review/controller/draft.logic';
import {
  installDailyReviewDraftAutosaveRuntime,
  runDailyReviewDraftAutosaveTick,
} from '../../../app/src/components/daily-review/controller/draftAutosave.runtime';

const repoRoot = process.cwd();
type DailyReviewDraftAutosaveTimerHost =
  Parameters<typeof installDailyReviewDraftAutosaveRuntime>[0]['timerHost'];

function buildDraft(
  overrides: Partial<PersistedDailyReviewDraft> = {},
): PersistedDailyReviewDraft {
  return {
    blockers: '',
    energy: null,
    expectedDate: '2026-04-23',
    learnings: '',
    mood: null,
    summary: 'Focused work',
    wins: '',
    ...overrides,
  };
}

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: DailyReviewDraftAutosaveTimerHost = {
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `timer-${callbacks.length}`;
    },
  };

  return {
    callbacks,
    clearedHandles,
    delays,
    host,
  };
}

test('daily review draft autosave tick serializes and persists the draft', () => {
  const draft = buildDraft({ wins: 'ship' });
  const persisted: string[] = [];
  const reports: unknown[] = [];

  runDailyReviewDraftAutosaveTick({
    draft,
    persistSerializedDraft: (serialized) => {
      persisted.push(serialized);
    },
    reportPersistError: (error) => {
      reports.push(error);
    },
    serializeDraft: (value) => JSON.stringify(value),
  });

  assert.deepEqual(persisted, [JSON.stringify(draft)]);
  assert.deepEqual(reports, []);
});

test('daily review draft autosave tick reports serialization and persistence failures', () => {
  const draft = buildDraft();
  const serializeFailure = new Error('serialize failed');
  const persistFailure = new Error('persist failed');
  const reports: unknown[] = [];

  runDailyReviewDraftAutosaveTick({
    draft,
    persistSerializedDraft: () => {
      throw persistFailure;
    },
    reportPersistError: (error) => {
      reports.push(error);
    },
    serializeDraft: () => 'serialized',
  });
  runDailyReviewDraftAutosaveTick({
    draft,
    persistSerializedDraft: () => {},
    reportPersistError: (error) => {
      reports.push(error);
    },
    serializeDraft: () => {
      throw serializeFailure;
    },
  });

  assert.deepEqual(reports, [persistFailure, serializeFailure]);
});

test('daily review draft autosave runtime schedules one delayed persist and clears it', () => {
  const timer = createTimerHost();
  const draft = buildDraft({ learnings: 'hydrate' });
  const persisted: string[] = [];

  const cleanup = installDailyReviewDraftAutosaveRuntime({
    delayMs: 500,
    draft,
    persistSerializedDraft: (serialized) => {
      persisted.push(serialized);
    },
    reportPersistError: () => {},
    serializeDraft: (value) => JSON.stringify(value),
    timerHost: timer.host,
  });

  assert.deepEqual(timer.delays, [500]);
  assert.deepEqual(persisted, []);
  timer.callbacks[0]?.();
  cleanup();

  assert.deepEqual(persisted, [JSON.stringify(draft)]);
  assert.deepEqual(timer.clearedHandles, ['timer-1']);
});

test('daily review controller delegates draft autosave timing to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/daily-review/controller/useDailyReviewController.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{ installDailyReviewDraftAutosaveRuntime \} from '\.\/draftAutosave\.runtime';/,
  );
  assert.match(
    source,
    /import \{[\s\S]*cleanupDailyReviewJustSavedReset,[\s\S]*createBrowserDailyReviewTimerHost,[\s\S]*createDailyReviewJustSavedRuntimeState,[\s\S]*scheduleDailyReviewJustSavedReset,[\s\S]*\} from '\.\/justSaved\.runtime';/,
  );
  assert.match(source, /installDailyReviewDraftAutosaveRuntime\(\{[\s\S]*delayMs: 500,[\s\S]*draft,[\s\S]*serializeDraft: serializeDailyReviewDraft,/);
  assert.match(
    source,
    /timerHost: createBrowserDailyReviewTimerHost\(\),/,
  );
  const testSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/tests/runtime/daily_review_draft_autosave_runtime.test.ts'),
    'utf8',
  );
  assert.doesNotMatch(testSource, /type DailyReviewDraftAutosaveTimerHost,\s*\n/);
  assert.doesNotMatch(source, /clearTimeout: \(handle\) => \{/);
  assert.doesNotMatch(source, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout/);
  assert.doesNotMatch(source, /const handle = window\.setTimeout\(\(\) => \{/);
  assert.doesNotMatch(source, /window\.clearTimeout\(handle\)/);
});
