import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  buildSettingsSectionIds,
  installSettingsScrollSpyRuntime,
  resolveFirstVisibleSettingsSection,
  SETTINGS_SCROLL_SPY_FALLBACK_MS,
} from '../../../app/src/components/settingsView.runtime';

const repoRoot = process.cwd();

test('settings scroll-spy section ids include optional sync and MCP sections in render order', () => {
  assert.deepEqual(
    buildSettingsSectionIds({ hasSyncBackends: true, supportsMcpHosting: true }),
    [
      'settings-section-general',
      'settings-section-appearance',
      'settings-section-sync',
      'settings-section-mcp',
      'settings-section-calendar',
      'settings-section-data',
    ],
  );
  assert.deepEqual(
    buildSettingsSectionIds({ hasSyncBackends: false, supportsMcpHosting: false }),
    [
      'settings-section-general',
      'settings-section-appearance',
      'settings-section-calendar',
      'settings-section-data',
    ],
  );
});

test('settings scroll-spy chooses the topmost visible section and ignores blank target ids', () => {
  assert.equal(
    resolveFirstVisibleSettingsSection([
      { isIntersecting: true, boundingClientRect: { top: 120 }, target: { id: 'settings-section-data' } },
      { isIntersecting: false, boundingClientRect: { top: 10 }, target: { id: 'hidden' } },
      { isIntersecting: true, boundingClientRect: { top: 30 }, target: { id: 'settings-section-general' } },
      { isIntersecting: true, boundingClientRect: { top: 0 }, target: { id: '' } },
    ]),
    'settings-section-general',
  );
  assert.equal(resolveFirstVisibleSettingsSection([]), null);
});

test('settings scroll-spy runtime observes mounted sections, suppresses programmatic-scroll flicker, and clears fallback timers', () => {
  const activeSections: string[] = [];
  const observed: string[] = [];
  const removedListeners: string[] = [];
  const scrolled: Array<{ id: string; behavior: 'auto' | 'smooth' }> = [];
  const clearedTimers: unknown[] = [];
  let observerCallback:
    | ((entries: Array<{ isIntersecting: boolean; boundingClientRect: { top: number }; target: { id: string } }>) => void)
    | null = null;
  let scrollEndListener: (() => void) | null = null;
  let nextTimerId = 1;

  const sectionElements = new Map([
    ['settings-section-general', {
      id: 'settings-section-general',
      scrollIntoView: (options: { behavior: 'auto' | 'smooth' }) => {
        scrolled.push({ id: 'settings-section-general', behavior: options.behavior });
      },
    }],
    ['settings-section-data', {
      id: 'settings-section-data',
      scrollIntoView: (options: { behavior: 'auto' | 'smooth' }) => {
        scrolled.push({ id: 'settings-section-data', behavior: options.behavior });
      },
    }],
  ]);

  const runtime = installSettingsScrollSpyRuntime({
    clearTimeout: (handle) => {
      clearedTimers.push(handle);
    },
    createIntersectionObserver: (callback) => {
      observerCallback = callback;
      return {
        disconnect: () => {
          observed.push('disconnect');
        },
        observe: (element) => {
          observed.push(element.id);
        },
      };
    },
    fallbackDelayMs: 25,
    getElementById: (id) => sectionElements.get(id) ?? null,
    readPrefersReducedMotion: () => false,
    scrollContainer: {
      addEventListener: (type, listener) => {
        assert.equal(type, 'scrollend');
        scrollEndListener = listener;
      },
      removeEventListener: (type) => {
        removedListeners.push(type);
      },
    },
    sectionIds: ['settings-section-general', 'missing-section', 'settings-section-data'],
    setActiveSection: (sectionId) => {
      activeSections.push(sectionId);
    },
    setTimeout: () => nextTimerId++,
  });

  assert.deepEqual(observed, ['settings-section-general', 'settings-section-data']);

  observerCallback?.([
    { isIntersecting: true, boundingClientRect: { top: 50 }, target: { id: 'settings-section-data' } },
  ]);
  runtime.navigate('settings-section-general');
  observerCallback?.([
    { isIntersecting: true, boundingClientRect: { top: 10 }, target: { id: 'settings-section-data' } },
  ]);
  scrollEndListener?.();
  observerCallback?.([
    { isIntersecting: true, boundingClientRect: { top: 10 }, target: { id: 'settings-section-data' } },
  ]);

  assert.deepEqual(activeSections, [
    'settings-section-data',
    'settings-section-general',
    'settings-section-data',
  ]);
  assert.deepEqual(scrolled, [{ id: 'settings-section-general', behavior: 'smooth' }]);
  assert.deepEqual(clearedTimers, [1]);

  runtime.navigate('missing-section');
  assert.deepEqual(activeSections, [
    'settings-section-data',
    'settings-section-general',
    'settings-section-data',
  ]);
  assert.deepEqual(scrolled, [{ id: 'settings-section-general', behavior: 'smooth' }]);
  assert.deepEqual(clearedTimers, [1]);

  runtime.cleanup();
  assert.deepEqual(clearedTimers, [1]);
  assert.deepEqual(removedListeners, ['scrollend']);
  assert.deepEqual(observed, ['settings-section-general', 'settings-section-data', 'disconnect']);

  runtime.navigate('settings-section-data');
  assert.deepEqual(scrolled, [{ id: 'settings-section-general', behavior: 'smooth' }]);
});

test('settings scroll-spy runtime honors reduced motion and clears pending fallback timer on cleanup', () => {
  const clearedTimers: unknown[] = [];
  const scrolled: Array<'auto' | 'smooth'> = [];
  const runtime = installSettingsScrollSpyRuntime({
    clearTimeout: (handle) => {
      clearedTimers.push(handle);
    },
    createIntersectionObserver: () => ({
      disconnect: () => {},
      observe: () => {},
    }),
    getElementById: () => ({
      id: 'settings-section-data',
      scrollIntoView: ({ behavior }) => {
        scrolled.push(behavior);
      },
    }),
    readPrefersReducedMotion: () => true,
    scrollContainer: {
      addEventListener: () => {},
      removeEventListener: () => {},
    },
    sectionIds: ['settings-section-data'],
    setActiveSection: () => {},
    setTimeout: (_callback, delayMs) => {
      assert.equal(delayMs, SETTINGS_SCROLL_SPY_FALLBACK_MS);
      return 'timer-id';
    },
  });

  runtime.navigate('settings-section-data');
  runtime.cleanup();

  assert.deepEqual(scrolled, ['auto']);
  assert.deepEqual(clearedTimers, ['timer-id']);
});

test('settings view delegates scroll-spy host wiring through guarded document/window seams', () => {
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settingsView.runtime.ts'),
    'utf8',
  );
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/SettingsView.tsx'),
    'utf8',
  );

  assert.ok(runtimeSource.includes('export function createBrowserSettingsScrollSpyTimerHost(): SettingsScrollSpyTimerHost'));
  assert.ok(
    runtimeSource.includes(
      'globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);',
    ),
  );
  assert.ok(runtimeSource.includes('setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),'));
  assert.ok(source.includes('createBrowserSettingsScrollSpyTimerHost,'));
  assert.ok(
    source.includes("const settingsDocument = typeof document === 'undefined' ? null : document;"),
  );
  assert.ok(
    source.includes("const settingsWindow = typeof window === 'undefined' ? undefined : window;"),
  );
  assert.ok(
    source.includes('const timerHost = createBrowserSettingsScrollSpyTimerHost();'),
  );
  assert.ok(
    source.includes('getElementById: (id) => settingsDocument?.getElementById(id) ?? null,'),
  );
  assert.ok(
    source.includes('readPrefersReducedMotion: () => prefersReducedMotion(settingsWindow),'),
  );
  assert.ok(
    source.includes('...timerHost,'),
  );
  assert.ok(!source.includes('globalThis.clearTimeout'));
  assert.ok(!source.includes('globalThis.setTimeout'));
  assert.ok(!source.includes('clearTimeout: (handle) => window.clearTimeout'));
  assert.ok(!source.includes('getElementById: (id) => document.getElementById'));
  assert.ok(!source.includes('readPrefersReducedMotion: () => prefersReducedMotion(window)'));
  assert.ok(!source.includes('setTimeout: (callback, delayMs) => window.setTimeout'));
});
