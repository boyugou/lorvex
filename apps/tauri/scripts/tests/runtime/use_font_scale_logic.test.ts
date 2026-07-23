import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  applyFontScale,
  clearPendingFontScaleAnimation,
  createFontScaleAnimationState,
  fontSizePxForScale,
  parseFontScale,
  snapFontScaleToNearest,
  type FontScaleRootHost,
  type FontScaleTimerApi,
} from '../../../app/src/lib/useFontScale.logic';

const repoRoot = process.cwd();

test('snapFontScaleToNearest picks the closest supported option', () => {
  assert.equal(snapFontScaleToNearest(0.91), 0.925);
  assert.equal(snapFontScaleToNearest(1.16), 1.2);
});

test('parseFontScale falls back for missing and malformed values', () => {
  assert.equal(parseFontScale(null), 1.0);
  assert.equal(parseFontScale('nope'), 1.0);
  assert.equal(parseFontScale('2.0'), 1.0);
  assert.equal(parseFontScale('0.9'), 1.0);
  assert.equal(parseFontScale('1.08'), 1.0);
  assert.equal(parseFontScale('1.0'), 1.0);
  assert.equal(parseFontScale('1e0'), 1.0);
});

test('parseFontScale accepts only canonical supported option payloads', () => {
  assert.equal(parseFontScale('0.85'), 0.85);
  assert.equal(parseFontScale('0.925'), 0.925);
  assert.equal(parseFontScale('1'), 1.0);
  assert.equal(parseFontScale('1.1'), 1.1);
  assert.equal(parseFontScale('1.2'), 1.2);
});

test('fontSizePxForScale converts scale to the root px value', () => {
  assert.equal(fontSizePxForScale(1.0), 16);
  assert.equal(fontSizePxForScale(1.2), 19.2);
});

test('applyFontScale without animation clears transition and sets font size', () => {
  const calls: string[] = [];
  const host: FontScaleRootHost = {
    addTransitionEndListener: () => { calls.push('add'); },
    clearTransition: () => { calls.push('clear'); },
    removeTransitionEndListener: () => { calls.push('remove'); },
    setTransition: () => { calls.push('transition'); },
    setFontSizePx: (fontSizePx) => { calls.push(`font:${fontSizePx}`); },
  };

  applyFontScale(host, 1.1, false);
  assert.deepEqual(calls, ['clear', 'font:17.6']);
});

test('applyFontScale with animation installs transition cleanup on transitionend and timeout', () => {
  let transitionEndListener: (() => void) | null = null;
  const scheduled: Array<() => void> = [];
  const calls: string[] = [];
  const state = createFontScaleAnimationState();
  const host: FontScaleRootHost = {
    addTransitionEndListener: (listener) => {
      transitionEndListener = listener;
      calls.push('add');
    },
    clearTransition: () => { calls.push('clear'); },
    removeTransitionEndListener: () => { calls.push('remove'); },
    setTransition: (transition) => { calls.push(`transition:${transition}`); },
    setFontSizePx: (fontSizePx) => { calls.push(`font:${fontSizePx}`); },
  };
  const timerApi: FontScaleTimerApi = {
    cancel: () => { calls.push('cancel'); },
    schedule: (callback, delayMs) => {
      assert.equal(delayMs, 300);
      scheduled.push(callback);
      return scheduled.length;
    },
  };

  applyFontScale(host, 1.2, true, state, timerApi);
  assert.deepEqual(calls, ['transition:font-size 0.2s ease', 'add', 'font:19.2']);

  transitionEndListener?.();
  assert.deepEqual(calls, ['transition:font-size 0.2s ease', 'add', 'font:19.2', 'cancel', 'clear']);

  scheduled[0]?.();
  assert.deepEqual(calls, ['transition:font-size 0.2s ease', 'add', 'font:19.2', 'cancel', 'clear', 'clear', 'remove']);
});

test('applyFontScale cancels the previous cleanup before starting a new animated update', () => {
  const scheduled: Array<() => void> = [];
  const calls: string[] = [];
  const listeners: Array<() => void> = [];
  const state = createFontScaleAnimationState();
  const host: FontScaleRootHost = {
    addTransitionEndListener: (listener) => {
      listeners.push(listener);
      calls.push(`add:${listeners.length}`);
    },
    clearTransition: () => { calls.push('clear'); },
    removeTransitionEndListener: () => { calls.push('remove'); },
    setTransition: (transition) => { calls.push(`transition:${transition}`); },
    setFontSizePx: (fontSizePx) => { calls.push(`font:${fontSizePx}`); },
  };
  const timerApi: FontScaleTimerApi = {
    cancel: () => { calls.push('cancel'); },
    schedule: (callback) => {
      scheduled.push(callback);
      return scheduled.length;
    },
  };

  applyFontScale(host, 1.1, true, state, timerApi);
  applyFontScale(host, 1.2, true, state, timerApi);

  assert.deepEqual(calls, [
    'transition:font-size 0.2s ease',
    'add:1',
    'font:17.6',
    'cancel',
    'remove',
    'transition:font-size 0.2s ease',
    'add:2',
    'font:19.2',
  ]);
});

test('applyFontScale cancels an animation timeout once transitionend already cleaned it up', () => {
  const scheduled: Array<() => void> = [];
  const listeners: Array<() => void> = [];
  const calls: string[] = [];
  const state = createFontScaleAnimationState();
  const host: FontScaleRootHost = {
    addTransitionEndListener: (listener) => {
      listeners.push(listener);
      calls.push(`add:${listeners.length}`);
    },
    clearTransition: () => { calls.push('clear'); },
    removeTransitionEndListener: () => { calls.push('remove'); },
    setTransition: (transition) => { calls.push(`transition:${transition}`); },
    setFontSizePx: (fontSizePx) => { calls.push(`font:${fontSizePx}`); },
  };
  const timerApi: FontScaleTimerApi = {
    cancel: () => { calls.push('cancel'); },
    schedule: (callback) => {
      scheduled.push(callback);
      return scheduled.length;
    },
  };

  applyFontScale(host, 1.1, true, state, timerApi);
  listeners[0]?.();
  applyFontScale(host, 1.2, true, state, timerApi);
  scheduled[0]?.();

  assert.deepEqual(calls, [
    'transition:font-size 0.2s ease',
    'add:1',
    'font:17.6',
    'cancel',
    'clear',
    'transition:font-size 0.2s ease',
    'add:2',
    'font:19.2',
    'clear',
    'remove',
  ]);
});

test('clearPendingFontScaleAnimation removes any pending timer/listener pair', () => {
  const calls: string[] = [];
  const state = createFontScaleAnimationState();
  const listener = () => {};
  state.cleanupHandle = 42;
  state.transitionEndListener = listener;
  const host: FontScaleRootHost = {
    addTransitionEndListener: () => {},
    clearTransition: () => {},
    removeTransitionEndListener: (removed) => {
      assert.equal(removed, listener);
      calls.push('remove');
    },
    setTransition: () => {},
    setFontSizePx: () => {},
  };
  const timerApi: FontScaleTimerApi = {
    cancel: (handle) => {
      assert.equal(handle, 42);
      calls.push('cancel');
    },
    schedule: () => 0,
  };

  clearPendingFontScaleAnimation(host, state, timerApi);

  assert.deepEqual(calls, ['cancel', 'remove']);
  assert.equal(state.cleanupHandle, null);
  assert.equal(state.transitionEndListener, null);
});

test('useFontScale delegates document-root host creation through the runtime helper', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/useFontScale.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/useFontScale.runtime.ts'),
    'utf8',
  );

  assert.ok(
    source.includes(
      "import { createBrowserFontScaleRootHost } from './useFontScale.runtime';",
    ),
  );
  assert.ok(source.includes('const host = createBrowserFontScaleRootHost();'));
  assert.ok(source.includes('if (!host) {'));
  assert.ok(!source.includes("document.documentElement.addEventListener('transitionend'"));

  assert.ok(runtimeSource.includes('export function createBrowserFontScaleRootHost(): FontScaleRootHost | null {'));
  assert.ok(runtimeSource.includes("if (typeof document === 'undefined') {"));
  assert.ok(runtimeSource.includes("document.documentElement.style.fontSize = `${fontSizePx}px`;"));
});
