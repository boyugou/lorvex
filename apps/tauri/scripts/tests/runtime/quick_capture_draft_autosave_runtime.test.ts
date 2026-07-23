import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserQuickCaptureDraftAutosaveTimerHost,
  hasQuickCaptureDraftContent,
  installQuickCaptureDraftAutosaveRuntime,
  QUICK_CAPTURE_DRAFT_STORAGE_KEY,
  runQuickCaptureDraftAutosaveTick,
  type QuickCaptureDraftAutosaveRuntimeDeps,
  type QuickCaptureDraftAutosaveSnapshot,
} from '../../../app/src/components/quick-capture/quickCaptureDraftAutosave.runtime';

const repoRoot = process.cwd();

function buildSnapshot(
  overrides: Partial<QuickCaptureDraftAutosaveSnapshot> = {},
): QuickCaptureDraftAutosaveSnapshot {
  return {
    body: '',
    selectedListId: null,
    tagsInput: '',
    title: '',
    ...overrides,
  };
}

function createHarness(
  overrides: Partial<QuickCaptureDraftAutosaveRuntimeDeps> = {},
) {
  const clearedTimeouts: unknown[] = [];
  const clearedDrafts: string[] = [];
  const persistedDrafts: string[] = [];
  const reportedErrors: unknown[] = [];
  const timeoutCallbacks: Array<() => void> = [];

  const deps: QuickCaptureDraftAutosaveRuntimeDeps = {
    clearDraft: () => {
      clearedDrafts.push('clear');
    },
    clearTimeout: (handle) => {
      clearedTimeouts.push(handle);
    },
    delayMs: 500,
    persistDraft: (serializedDraft) => {
      persistedDrafts.push(serializedDraft);
    },
    reportPersistError: (error) => {
      reportedErrors.push(error);
    },
    setTimeout: (callback) => {
      timeoutCallbacks.push(callback);
      return `timer-${timeoutCallbacks.length}`;
    },
    snapshot: buildSnapshot(),
    ...overrides,
  };

  return {
    clearedDrafts,
    clearedTimeouts,
    deps,
    persistedDrafts,
    reportedErrors,
    timeoutCallbacks,
  };
}

test('quick capture draft autosave content detector trims expensive-to-retype fields', () => {
  assert.equal(hasQuickCaptureDraftContent(buildSnapshot()), false);
  assert.equal(hasQuickCaptureDraftContent(buildSnapshot({ title: '  ' })), false);
  assert.equal(hasQuickCaptureDraftContent(buildSnapshot({ title: 'Inbox zero' })), true);
  assert.equal(hasQuickCaptureDraftContent(buildSnapshot({ body: 'notes' })), true);
  assert.equal(hasQuickCaptureDraftContent(buildSnapshot({ tagsInput: 'ops' })), true);
});

test('quick capture draft autosave tick clears empty drafts without reporting clear failures', () => {
  const failure = new Error('remove failed');
  const harness = createHarness({
    clearDraft: () => {
      throw failure;
    },
  });

  runQuickCaptureDraftAutosaveTick(harness.deps);

  assert.deepEqual(harness.persistedDrafts, []);
  assert.deepEqual(harness.reportedErrors, []);
});

test('quick capture draft autosave tick serializes non-empty drafts exactly', () => {
  const snapshot = buildSnapshot({
    body: 'Details',
    selectedListId: 'list-1',
    tagsInput: 'alpha, beta',
    title: 'Plan launch',
  });
  const harness = createHarness({ snapshot });

  runQuickCaptureDraftAutosaveTick(harness.deps);

  assert.deepEqual(harness.clearedDrafts, []);
  assert.deepEqual(harness.reportedErrors, []);
  assert.deepEqual(harness.persistedDrafts, [JSON.stringify(snapshot)]);
});

test('quick capture draft autosave tick reports persist failures', () => {
  const failure = new Error('quota exceeded');
  const harness = createHarness({
    persistDraft: () => {
      throw failure;
    },
    snapshot: buildSnapshot({ title: 'Still worth saving' }),
  });

  runQuickCaptureDraftAutosaveTick(harness.deps);

  assert.deepEqual(harness.reportedErrors, [failure]);
});

test('quick capture draft autosave runtime schedules one delayed tick and clears it', () => {
  const harness = createHarness({
    snapshot: buildSnapshot({ title: 'Delayed draft' }),
  });

  const cleanup = installQuickCaptureDraftAutosaveRuntime(harness.deps);
  assert.equal(harness.timeoutCallbacks.length, 1);
  assert.deepEqual(harness.persistedDrafts, []);

  harness.timeoutCallbacks[0]?.();
  cleanup();

  assert.deepEqual(harness.persistedDrafts, [JSON.stringify(harness.deps.snapshot)]);
  assert.deepEqual(harness.clearedTimeouts, ['timer-1']);
});

test('quick capture draft autosave exposes the canonical storage key', () => {
  assert.equal(QUICK_CAPTURE_DRAFT_STORAGE_KEY, 'lorvex.quickCapture.draft');
});

test('quick capture form delegates draft autosave to the runtime seam', () => {
  const formSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/quick-capture/useQuickCaptureForm.ts'),
    'utf8',
  );
  const draftSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/quick-capture/useQuickCaptureDraft.ts'),
    'utf8',
  );

  assert.match(formSource, /useQuickCaptureDraftAutosave\(\{/);
  assert.match(
    draftSource,
    /import \{[\s\S]*createBrowserQuickCaptureDraftAutosaveTimerHost,[\s\S]*installQuickCaptureDraftAutosaveRuntime,[\s\S]*QUICK_CAPTURE_DRAFT_STORAGE_KEY,[\s\S]*\} from '\.\/quickCaptureDraftAutosave\.runtime';/,
  );
  assert.match(draftSource, /const quickCaptureDraftAutosaveTimerHost = createBrowserQuickCaptureDraftAutosaveTimerHost\(\);/);
  assert.match(draftSource, /installQuickCaptureDraftAutosaveRuntime\(\{/);
  assert.match(
    draftSource,
    /\.\.\.quickCaptureDraftAutosaveTimerHost,/,
  );
  assert.match(draftSource, /snapshot: \{ title, body, tagsInput, selectedListId \}/);
  assert.doesNotMatch(draftSource, /globalThis\.setTimeout/);
  assert.doesNotMatch(draftSource, /globalThis\.clearTimeout/);
  assert.doesNotMatch(draftSource, /const handle = window\.setTimeout\(\(\) => \{/);
  assert.doesNotMatch(draftSource, /const DRAFT_STORAGE_KEY = 'lorvex\.quickCapture\.draft';/);
});

test('quick capture draft autosave runtime owns the browser timer host wiring', () => {
  const host = createBrowserQuickCaptureDraftAutosaveTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');

  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/quick-capture/quickCaptureDraftAutosave.runtime.ts'),
    'utf8',
  );

  assert.match(source, /export function createBrowserQuickCaptureDraftAutosaveTimerHost\(\): Pick</);
  assert.match(
    source,
    /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/,
  );
  assert.match(source, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});
