import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserAssistantUiPollingTimerHost,
  installAssistantUiPollingRuntime,
  pollAssistantUiCommand,
  type AssistantUiPollingRuntimeOptions,
} from '../../../app/src/app-shell/main-window/runtime/useAssistantUiRuntime.runtime';

const repoRoot = process.cwd();

function createDeferred<T>() {
  let resolve: (value: T) => void = () => {};
  let reject: (error: unknown) => void = () => {};
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, reject, resolve };
}

function createHarness(initialVisibility: 'visible' | 'hidden' = 'visible') {
  const visibilityHandlers = new Set<() => void>();
  const timerCallbacks: Array<() => void> = [];
  const timerDelays: number[] = [];
  const clearedHandles: unknown[] = [];
  let visibilityState: 'visible' | 'hidden' = initialVisibility;
  let pollCount = 0;

  const runtime = {
    cleanup: () => {},
    fireVisibilityChange: (nextVisibility: 'visible' | 'hidden') => {
      visibilityState = nextVisibility;
      for (const handler of visibilityHandlers) {
        handler();
      }
    },
    flushTimer: (index: number) => {
      timerCallbacks[index]?.();
    },
    pollCount: () => pollCount,
    setPollImplementation: (impl: AssistantUiPollingRuntimeOptions['poll']) => {
      poll = async () => {
        pollCount += 1;
        await impl();
      };
    },
    timerDelays,
    clearedHandles,
    visibilityHandlers,
  };

  let poll: AssistantUiPollingRuntimeOptions['poll'] = async () => {
    pollCount += 1;
  };

  runtime.cleanup = installAssistantUiPollingRuntime({
    addVisibilityListener: (handler) => {
      visibilityHandlers.add(handler);
      return () => {
        visibilityHandlers.delete(handler);
      };
    },
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    getVisibilityState: () => visibilityState,
    poll: () => poll(),
    setTimeout: (callback, delayMs) => {
      timerCallbacks.push(callback);
      timerDelays.push(delayMs);
      return `timer-${timerCallbacks.length}` as ReturnType<typeof globalThis.setTimeout>;
    },
  });

  return runtime;
}

test('assistant UI polling runtime starts immediately when visible and reschedules after each poll', async () => {
  const harness = createHarness('visible');

  await Promise.resolve();
  await Promise.resolve();

  assert.equal(harness.pollCount(), 1);
  assert.deepEqual(harness.timerDelays, [1500]);

  harness.flushTimer(0);
  await Promise.resolve();
  await Promise.resolve();

  assert.equal(harness.pollCount(), 2);
  assert.deepEqual(harness.timerDelays, [1500, 1500]);
});

test('assistant UI polling runtime waits for visibility before starting when hidden', async () => {
  const harness = createHarness('hidden');

  await Promise.resolve();
  assert.equal(harness.pollCount(), 0);
  assert.deepEqual(harness.timerDelays, []);

  harness.fireVisibilityChange('visible');
  await Promise.resolve();
  await Promise.resolve();

  assert.equal(harness.pollCount(), 1);
  assert.deepEqual(harness.timerDelays, [1500]);
});

test('assistant UI polling runtime clears a pending timer when the document becomes hidden', async () => {
  const harness = createHarness('visible');

  await Promise.resolve();
  await Promise.resolve();

  harness.fireVisibilityChange('hidden');

  assert.deepEqual(harness.clearedHandles, ['timer-1']);
});

test('assistant UI polling runtime unregisters listeners and clears timers on cleanup', async () => {
  const harness = createHarness('visible');

  await Promise.resolve();
  await Promise.resolve();
  harness.cleanup();

  assert.deepEqual(harness.clearedHandles, ['timer-1']);
  assert.equal(harness.visibilityHandlers.size, 0);
});

test('assistant UI command poll suppresses side effects after cleanup before device state resolves', async () => {
  const rawCommand = JSON.stringify({
    command_id: 'cmd-open',
    action: 'open_task',
    task_id: 'task-1',
  });
  const commandRead = createDeferred<string | null>();
  const handledIdRead = createDeferred<string | null>();
  const commands: unknown[] = [];
  const errors: unknown[] = [];
  const writes: Array<[string, string | null]> = [];
  let cancelled = false;
  let handledCommandId: string | null = null;

  const pollPromise = pollAssistantUiCommand({
    executeCommand: async (command) => {
      commands.push(command);
    },
    getDeviceState: (key) => (
      key === 'assistant_ui_command'
        ? commandRead.promise
        : handledIdRead.promise
    ),
    getHandledCommandId: () => handledCommandId,
    isCancelled: () => cancelled,
    reportClientError: (...args) => {
      errors.push(args);
    },
    setDeviceState: async (key, value) => {
      writes.push([key, value]);
    },
    setHandledCommandId: (commandId) => {
      handledCommandId = commandId;
    },
  });

  cancelled = true;
  commandRead.resolve(rawCommand);
  handledIdRead.resolve(null);
  await pollPromise;

  assert.deepEqual(commands, []);
  assert.deepEqual(errors, []);
  assert.deepEqual(writes, []);
  assert.equal(handledCommandId, null);
});

test('assistant UI command poll suppresses handled-id persistence when cleanup happens during command execution', async () => {
  const rawCommand = JSON.stringify({
    command_id: 'cmd-open',
    action: 'open_task',
    task_id: 'task-1',
  });
  const commands: unknown[] = [];
  const writes: Array<[string, string | null]> = [];
  let cancelled = false;
  let handledCommandId: string | null = null;

  await pollAssistantUiCommand({
    executeCommand: async (command) => {
      commands.push(command);
      cancelled = true;
    },
    getDeviceState: async (key) => (
      key === 'assistant_ui_command'
        ? rawCommand
        : null
    ),
    getHandledCommandId: () => handledCommandId,
    isCancelled: () => cancelled,
    reportClientError: () => {},
    setDeviceState: async (key, value) => {
      writes.push([key, value]);
    },
    setHandledCommandId: (commandId) => {
      handledCommandId = commandId;
    },
  });

  assert.equal(commands.length, 1);
  assert.deepEqual(writes, []);
  assert.equal(handledCommandId, null);
});

test('assistant UI hook delegates visibility-gated polling through the browser host seam', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/runtime/useAssistantUiRuntime.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/runtime/useAssistantUiRuntime.runtime.ts'),
    'utf8',
  );

  assert.ok(
    source.includes(
      'createBrowserAssistantUiPollingTimerHost,',
    ),
  );
  assert.ok(source.includes('const assistantUiPollingTimerHost = createBrowserAssistantUiPollingTimerHost();'));
  assert.ok(source.includes('return installAssistantUiPollingRuntime({'));
  assert.ok(source.includes("document.addEventListener('visibilitychange', handler);"));
  assert.ok(
    source.includes(
      'getVisibilityState: () => (typeof document === \'undefined\' ? \'visible\' : document.visibilityState),',
    ),
  );
  assert.ok(source.includes('...assistantUiPollingTimerHost,'));
  assert.ok(!source.includes('globalThis.setTimeout'));
  assert.ok(!source.includes('globalThis.clearTimeout'));
  assert.ok(!source.includes('window.setTimeout('));
  assert.ok(!source.includes('window.clearTimeout('));
  assert.ok(!source.includes("document.addEventListener('visibilitychange', onVisibilityChange)"));

  assert.ok(runtimeSource.includes('export function createBrowserAssistantUiPollingTimerHost(): AssistantUiPollingTimerHost'));
  assert.ok(
    runtimeSource.includes(
      'globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);',
    ),
  );
  assert.ok(runtimeSource.includes('setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),'));
});

test('assistant UI polling runtime owns the browser timer host wiring', () => {
  const host = createBrowserAssistantUiPollingTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
