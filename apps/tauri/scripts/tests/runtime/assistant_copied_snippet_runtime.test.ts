import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  cleanupAssistantCopiedSnippetReset,
  createBrowserAssistantCopiedSnippetTimerHost,
  createAssistantCopiedSnippetRuntimeState,
  scheduleAssistantCopiedSnippetReset,
  type AssistantCopiedSnippetTimerHost,
} from '../../../app/src/components/settings/controller/assistant/copiedSnippet.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: AssistantCopiedSnippetTimerHost = {
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

function createSnippetState(initial: string | null) {
  let copiedSnippet = initial;
  return {
    get value() {
      return copiedSnippet;
    },
    setCopiedSnippet: (updater: (current: string | null) => string | null) => {
      copiedSnippet = updater(copiedSnippet);
    },
  };
}

test('assistant copied-snippet runtime schedules a mounted reset for the matching key', () => {
  const timer = createTimerHost();
  const state = createAssistantCopiedSnippetRuntimeState();
  const snippet = createSnippetState('codex');

  scheduleAssistantCopiedSnippetReset({
    delayMs: 2000,
    isMounted: () => true,
    key: 'codex',
    setCopiedSnippet: snippet.setCopiedSnippet,
    state,
    timerHost: timer.host,
  });

  assert.equal(state.resetTimer, 'timer-1');
  assert.deepEqual(timer.delays, [2000]);
  assert.equal(snippet.value, 'codex');

  timer.callbacks[0]?.();

  assert.equal(state.resetTimer, null);
  assert.equal(snippet.value, null);
});

test('assistant copied-snippet runtime preserves newer copied keys when an old reset fires', () => {
  const timer = createTimerHost();
  const state = createAssistantCopiedSnippetRuntimeState();
  const snippet = createSnippetState('claudeDesktop');

  scheduleAssistantCopiedSnippetReset({
    delayMs: 2000,
    isMounted: () => true,
    key: 'codex',
    setCopiedSnippet: snippet.setCopiedSnippet,
    state,
    timerHost: timer.host,
  });
  timer.callbacks[0]?.();

  assert.equal(snippet.value, 'claudeDesktop');
  assert.equal(state.resetTimer, null);
});

test('assistant copied-snippet runtime cancels an older reset before scheduling a newer one', () => {
  const timer = createTimerHost();
  const state = createAssistantCopiedSnippetRuntimeState();
  const snippet = createSnippetState('codex');

  const deps = {
    delayMs: 2000,
    isMounted: () => true,
    key: 'codex',
    setCopiedSnippet: snippet.setCopiedSnippet,
    state,
    timerHost: timer.host,
  };

  scheduleAssistantCopiedSnippetReset(deps);
  scheduleAssistantCopiedSnippetReset(deps);
  timer.callbacks[1]?.();

  assert.deepEqual(timer.clearedHandles, ['timer-1']);
  assert.equal(snippet.value, null);
  assert.equal(state.resetTimer, null);
});

test('assistant copied-snippet runtime suppresses reset after unmount', () => {
  const timer = createTimerHost();
  const state = createAssistantCopiedSnippetRuntimeState();
  const snippet = createSnippetState('setupPrompt');

  scheduleAssistantCopiedSnippetReset({
    delayMs: 2000,
    isMounted: () => false,
    key: 'setupPrompt',
    setCopiedSnippet: snippet.setCopiedSnippet,
    state,
    timerHost: timer.host,
  });
  timer.callbacks[0]?.();

  assert.equal(snippet.value, 'setupPrompt');
  assert.equal(state.resetTimer, null);
});

test('assistant copied-snippet runtime cleanup clears a pending timer once', () => {
  const timer = createTimerHost();
  const state = createAssistantCopiedSnippetRuntimeState();
  const snippet = createSnippetState('codex');

  scheduleAssistantCopiedSnippetReset({
    delayMs: 2000,
    isMounted: () => true,
    key: 'codex',
    setCopiedSnippet: snippet.setCopiedSnippet,
    state,
    timerHost: timer.host,
  });
  cleanupAssistantCopiedSnippetReset(state, timer.host);
  cleanupAssistantCopiedSnippetReset(state, timer.host);

  assert.deepEqual(timer.clearedHandles, ['timer-1']);
  assert.equal(state.resetTimer, null);
});

test('assistant MCP controller delegates copied-snippet timing to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/assistant/mcp.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*cleanupAssistantCopiedSnippetReset,[\s\S]*createBrowserAssistantCopiedSnippetTimerHost,[\s\S]*createAssistantCopiedSnippetRuntimeState,[\s\S]*scheduleAssistantCopiedSnippetReset,[\s\S]*\} from '\.\/copiedSnippet\.runtime';/,
  );
  assert.match(
    source,
    /const copiedSnippetRuntimeStateRef = useLazyRef\(\(\) => createAssistantCopiedSnippetRuntimeState\(\)\);/,
  );
  assert.match(
    source,
    /const copiedSnippetTimerHostRef = useLazyRef\(\(\) => createBrowserAssistantCopiedSnippetTimerHost\(\)\);/,
  );
  assert.match(source, /scheduleAssistantCopiedSnippetReset\(\{[\s\S]*delayMs: 2000,[\s\S]*isMounted: \(\) => settingsMountedRef\.current,[\s\S]*key,[\s\S]*setCopiedSnippet,/);
  assert.match(
    source,
    /timerHost: copiedSnippetTimerHostRef\.current,/,
  );
  assert.match(
    source,
    /cleanupAssistantCopiedSnippetReset\([\s\S]*copiedSnippetRuntimeStateRef\.current,[\s\S]*copiedSnippetTimerHostRef\.current,[\s\S]*\);/s,
  );
  assert.doesNotMatch(source, /copiedSnippetResetTimerRef/);
  assert.doesNotMatch(source, /globalThis\.setTimeout/);
  assert.doesNotMatch(source, /globalThis\.clearTimeout/);
  assert.doesNotMatch(source, /window\.setTimeout\(\(\) => \{\s*if \(!settingsMountedRef\.current\)/);
  assert.doesNotMatch(source, /window\.setTimeout\(/);
  assert.doesNotMatch(source, /window\.clearTimeout\(/);
});

test('assistant copied-snippet runtime owns the browser timer host wiring', () => {
  const host = createBrowserAssistantCopiedSnippetTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');

  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/assistant/copiedSnippet.runtime.ts'),
    'utf8',
  );

  assert.match(source, /export function createBrowserAssistantCopiedSnippetTimerHost\(\): AssistantCopiedSnippetTimerHost/);
  assert.match(
    source,
    /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/,
  );
  assert.match(source, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});
