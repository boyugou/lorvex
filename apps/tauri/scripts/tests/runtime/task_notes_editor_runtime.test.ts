import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserTaskNotesSaveTimerHost,
  createTaskNotesSaveState,
  flushTaskNotesSave,
  scheduleTaskNotesSave,
  TASK_NOTES_SAVE_DEBOUNCE_MS,
  type TaskNotesSaveTimerHost,
} from '../../../app/src/components/task-detail/task-notes-editor/TaskNotesEditor.runtime';

function createSaveTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: TaskNotesSaveTimerHost = {
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `notes-save-timer-${callbacks.length}`;
    },
  };

  return {
    callbacks,
    clearedHandles,
    delays,
    host,
  };
}

test('task notes save scheduling replaces stale timers and persists the latest markdown', () => {
  const timer = createSaveTimerHost();
  const state = createTaskNotesSaveState();
  const persisted: string[] = [];
  const persistBody = async (markdown?: string) => {
    persisted.push(markdown ?? '');
    return true;
  };

  scheduleTaskNotesSave({
    state,
    timerHost: timer.host,
    pending: { persistBody, markdown: 'first' },
  });
  assert.equal(state.timer, 'notes-save-timer-1');
  assert.deepEqual(timer.delays, [TASK_NOTES_SAVE_DEBOUNCE_MS]);

  scheduleTaskNotesSave({
    state,
    timerHost: timer.host,
    pending: { persistBody, markdown: 'second' },
  });
  assert.deepEqual(timer.clearedHandles, ['notes-save-timer-1']);
  assert.equal(state.timer, 'notes-save-timer-2');

  timer.callbacks[1]?.();
  assert.deepEqual(persisted, ['second']);
  assert.deepEqual(state, { timer: null, pending: null });
});

test('task notes flush clears pending timer and persists the captured markdown immediately', () => {
  const timer = createSaveTimerHost();
  const state = createTaskNotesSaveState();
  const persisted: string[] = [];

  scheduleTaskNotesSave({
    state,
    timerHost: timer.host,
    pending: {
      persistBody: async (markdown?: string) => {
        persisted.push(markdown ?? '');
        return true;
      },
      markdown: 'draft before task switch',
    },
  });

  flushTaskNotesSave(state, timer.host.clearTimeout);

  assert.deepEqual(timer.clearedHandles, ['notes-save-timer-1']);
  assert.deepEqual(persisted, ['draft before task switch']);
  assert.deepEqual(state, { timer: null, pending: null });
});

test('task notes editor delegates save timer wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/task-detail/task-notes-editor/TaskNotesEditor.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/task-detail/task-notes-editor/TaskNotesEditor.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserTaskNotesSaveTimerHost,[\s\S]*createTaskNotesSaveState,[\s\S]*flushTaskNotesSave,[\s\S]*scheduleTaskNotesSave,[\s\S]*type TaskNotesSaveState,[\s\S]*\} from '\.\/TaskNotesEditor\.runtime';/s,
  );
  assert.match(source, /const taskNotesSaveTimerHost = createBrowserTaskNotesSaveTimerHost\(\);/);
  assert.match(
    source,
    /scheduleTaskNotesSave\(\{[\s\S]*state: saveStateRef\.current,[\s\S]*timerHost: taskNotesSaveTimerHost,[\s\S]*pending: \{ persistBody, markdown \},[\s\S]*\}\);/s,
  );
  assert.match(
    source,
    /flushTaskNotesSave\([\s\S]*saveStateRef\.current,[\s\S]*taskNotesSaveTimerHost\.clearTimeout,[\s\S]*\);/s,
  );
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);
  assert.doesNotMatch(source, /(?<!\.)\bclearTimeout\(/);

  assert.match(runtimeSource, /export function createBrowserTaskNotesSaveTimerHost\(\): TaskNotesSaveTimerHost/);
  assert.match(runtimeSource, /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('task notes editor runtime owns the browser save timer host wiring', () => {
  const host = createBrowserTaskNotesSaveTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
