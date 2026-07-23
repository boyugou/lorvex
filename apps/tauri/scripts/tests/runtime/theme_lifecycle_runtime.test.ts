import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserThemeMediaRuntimeDeps,
  createBrowserThemeVisibilityRefreshRuntimeDeps,
  installThemeMediaRuntime,
  installThemeVisibilityRefreshRuntime,
  resolveThemeMediaSystemTheme,
} from '../../../app/src/lib/theme/lifecycle.runtime';

test('theme visibility refresh runtime re-applies on focus and on visible visibility changes only, then cleans up', () => {
  const calls: string[] = [];
  let hidden = true;
  const documentListeners = new Map<'visibilitychange', () => void>();
  const windowListeners = new Map<'focus', () => void>();

  const cleanup = installThemeVisibilityRefreshRuntime({
    documentTarget: {
      addEventListener: (type, listener) => {
        documentListeners.set(type, listener);
      },
      removeEventListener: (type, listener) => {
        if (documentListeners.get(type) === listener) {
          documentListeners.delete(type);
        }
      },
      get hidden() {
        return hidden;
      },
    },
    reapply: () => {
      calls.push('reapply');
    },
    windowTarget: {
      addEventListener: (type, listener) => {
        windowListeners.set(type, listener);
      },
      removeEventListener: (type, listener) => {
        if (windowListeners.get(type) === listener) {
          windowListeners.delete(type);
        }
      },
    },
  });

  windowListeners.get('focus')?.();
  documentListeners.get('visibilitychange')?.();
  hidden = false;
  documentListeners.get('visibilitychange')?.();

  assert.deepEqual(calls, ['reapply', 'reapply']);

  cleanup();
  assert.equal(documentListeners.size, 0);
  assert.equal(windowListeners.size, 0);
});

test('theme browser visibility deps own document and window host wiring', () => {
  const originalDocument = Object.getOwnPropertyDescriptor(globalThis, 'document');
  const originalWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');
  const documentTarget = { hidden: false };
  const windowTarget = {};

  try {
    Object.defineProperty(globalThis, 'document', {
      configurable: true,
      value: documentTarget,
    });
    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: windowTarget,
    });

    const deps = createBrowserThemeVisibilityRefreshRuntimeDeps(() => {});
    assert.equal(deps?.documentTarget, documentTarget);
    assert.equal(deps?.windowTarget, windowTarget);
  } finally {
    if (originalDocument) {
      Object.defineProperty(globalThis, 'document', originalDocument);
    } else {
      Reflect.deleteProperty(globalThis, 'document');
    }
    if (originalWindow) {
      Object.defineProperty(globalThis, 'window', originalWindow);
    } else {
      Reflect.deleteProperty(globalThis, 'window');
    }
  }
});

test('theme media runtime uses modern change listeners and resolves system mode through the supplied mapper', () => {
  const applied: Array<{ mode: string; resolved: string; force: true }> = [];
  const systemThemes: Array<'dark' | 'light'> = [];
  let changeListener: ((event: { matches: boolean }) => void) | null = null;

  const cleanup = installThemeMediaRuntime({
    applyNativeTheme: (mode, resolved, options) => {
      applied.push({ mode, resolved, force: options.force });
    },
    createMediaQueryList: () => ({
      addEventListener: (_type, listener) => {
        changeListener = listener;
      },
      removeEventListener: (_type, listener) => {
        if (changeListener === listener) {
          changeListener = null;
        }
      },
    }),
    readLatestTheme: () => ({ mode: 'system', resolved: 'dark' }),
    resolveSystemTheme: (systemTheme) => (systemTheme === 'light' ? 'paper' : 'ember'),
    setSystemTheme: (systemTheme) => {
      systemThemes.push(systemTheme);
    },
  });

  changeListener?.({ matches: true });

  assert.deepEqual(systemThemes, ['light']);
  assert.deepEqual(applied, [{ mode: 'system', resolved: 'paper', force: true }]);

  cleanup();
  assert.equal(changeListener, null);
});

test('theme media runtime ignores legacy addListener/removeListener-only queries', () => {
  const applied: Array<{ mode: string; resolved: string; force: true }> = [];
  const systemThemes: Array<'dark' | 'light'> = [];
  let changeListener: ((event: { matches: boolean }) => void) | null = null;

  const cleanup = installThemeMediaRuntime({
    applyNativeTheme: (mode, resolved, options) => {
      applied.push({ mode, resolved, force: options.force });
    },
    createMediaQueryList: () => ({
      addListener: (listener) => {
        changeListener = listener;
      },
      removeListener: (listener) => {
        if (changeListener === listener) {
          changeListener = null;
        }
      },
    }),
    readLatestTheme: () => ({ mode: 'mica', resolved: 'mica' }),
    resolveSystemTheme: (systemTheme) => (systemTheme === 'light' ? 'paper' : 'ember'),
    setSystemTheme: (systemTheme) => {
      systemThemes.push(systemTheme);
    },
  });

  assert.equal(changeListener, null);
  changeListener?.({ matches: false });

  assert.deepEqual(systemThemes, []);
  assert.deepEqual(applied, []);

  cleanup();
  assert.equal(changeListener, null);
});

test('theme media runtime fails closed when media query creation throws and the system-theme mapping stays canonical', () => {
  const cleanup = installThemeMediaRuntime({
    applyNativeTheme: () => {
      throw new Error('should not run');
    },
    createMediaQueryList: () => {
      throw new Error('unsupported');
    },
    readLatestTheme: () => ({ mode: 'system', resolved: 'dark' }),
    resolveSystemTheme: (systemTheme) => (systemTheme === 'light' ? 'light' : 'dark'),
    setSystemTheme: () => {
      throw new Error('should not run');
    },
  });

  cleanup();
  assert.equal(resolveThemeMediaSystemTheme(true), 'light');
  assert.equal(resolveThemeMediaSystemTheme(false), 'dark');
});

test('theme browser media deps own matchMedia host wiring', () => {
  const originalWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');
  const queries: string[] = [];

  try {
    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: {
        matchMedia: (query: string) => {
          queries.push(query);
          return {};
        },
      },
    });

    const deps = createBrowserThemeMediaRuntimeDeps({
      applyNativeTheme: () => {},
      readLatestTheme: () => ({ mode: 'system', resolved: 'dark' }),
      resolveSystemTheme: (systemTheme) => systemTheme,
      setSystemTheme: () => {},
    });

    assert.notEqual(deps, null);
    deps?.createMediaQueryList();
    assert.deepEqual(queries, ['(prefers-color-scheme: light)']);
  } finally {
    if (originalWindow) {
      Object.defineProperty(globalThis, 'window', originalWindow);
    } else {
      Reflect.deleteProperty(globalThis, 'window');
    }
  }
});

test('theme lifecycle hook delegates browser visibility and media host wiring to runtime helpers', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/theme/lifecycle.ts'),
    'utf8',
  );

  assert.match(source, /createBrowserThemeVisibilityRefreshRuntimeDeps/);
  assert.match(source, /createBrowserThemeMediaRuntimeDeps/);
  assert.match(source, /applySystemThemeAttribute/);
  assert.match(source, /getThemeWindowKind/);
  assert.doesNotMatch(source, /documentTarget:\s*document/);
  assert.doesNotMatch(source, /windowTarget:\s*window/);
  assert.doesNotMatch(source, /typeof window === 'undefined' \|\| typeof window\.matchMedia !== 'function'/);
  assert.doesNotMatch(source, /createMediaQueryList: \(\) => window\.matchMedia/);
  assert.doesNotMatch(source, /document\.documentElement/);
});
