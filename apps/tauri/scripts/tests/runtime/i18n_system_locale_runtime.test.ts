import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  applyBrowserLocaleDocumentAttributes,
  createBrowserI18nPreferenceLoadTimeoutHost,
  createBrowserI18nSystemLocaleRefreshRuntimeDeps,
  I18N_PREFERENCE_LOAD_TIMEOUT_MS,
  installI18nSystemLocaleRefreshRuntime,
  scheduleI18nPreferenceLoadTimeout,
  reconcileSystemLocaleRefresh,
  type I18nPreferenceLoadTimeoutHost,
} from '../../../app/src/lib/dates/i18nSystemLocale.runtime';
import type { Locale } from '../../../app/src/locales';

test('i18n system-locale refresh ignores hidden documents and no-op locale matches', () => {
  assert.equal(reconcileSystemLocaleRefresh('en', 'zh', 'hidden'), null);
  assert.equal(reconcileSystemLocaleRefresh('en', 'en', 'visible'), null);
  assert.equal(reconcileSystemLocaleRefresh('en', 'zh', 'visible'), 'zh');
});

test('i18n browser locale document attributes own lang and dir host writes', () => {
  const originalDocument = Object.getOwnPropertyDescriptor(globalThis, 'document');
  const documentElement = { lang: '', dir: '' };

  try {
    Object.defineProperty(globalThis, 'document', {
      configurable: true,
      value: { documentElement },
    });

    applyBrowserLocaleDocumentAttributes('ur');
    assert.deepEqual(documentElement, { lang: 'ur', dir: 'rtl' });

    applyBrowserLocaleDocumentAttributes('zh');
    assert.deepEqual(documentElement, { lang: 'zh', dir: 'ltr' });
  } finally {
    if (originalDocument) {
      Object.defineProperty(globalThis, 'document', originalDocument);
    } else {
      Reflect.deleteProperty(globalThis, 'document');
    }
  }
});

test('i18n system-locale runtime does not install listeners when system-follow mode is disabled', () => {
  let documentListeners = 0;
  let windowListeners = 0;

  const cleanup = installI18nSystemLocaleRefreshRuntime({
    enabled: false,
    addDocumentListener: () => {
      documentListeners += 1;
      return () => {};
    },
    addWindowListener: () => {
      windowListeners += 1;
      return () => {};
    },
    applyLocale: () => {},
    currentLocale: 'en',
    detectSystemLocale: () => 'zh',
    getVisibilityState: () => 'visible',
  });

  cleanup();
  assert.equal(documentListeners, 0);
  assert.equal(windowListeners, 0);
});

test('i18n system-locale runtime applies a newly detected locale once per new visible system-locale value and cleans up', () => {
  const applied: Locale[] = [];
  const documentListeners = new Map<'visibilitychange', () => void>();
  const windowListeners = new Map<'focus', () => void>();

  const cleanup = installI18nSystemLocaleRefreshRuntime({
    enabled: true,
    addDocumentListener: (type, listener) => {
      documentListeners.set(type, listener);
      return () => {
        documentListeners.delete(type);
      };
    },
    addWindowListener: (type, listener) => {
      windowListeners.set(type, listener);
      return () => {
        windowListeners.delete(type);
      };
    },
    applyLocale: (locale) => {
      applied.push(locale);
    },
    currentLocale: 'en',
    detectSystemLocale: () => 'zh',
    getVisibilityState: () => 'visible',
  });

  documentListeners.get('visibilitychange')?.();
  windowListeners.get('focus')?.();

  assert.deepEqual(applied, ['zh']);

  cleanup();
  assert.equal(documentListeners.size, 0);
  assert.equal(windowListeners.size, 0);
});

test('i18n system-locale runtime still reconciles visibility without browser listener hosts', () => {
  const applied: Locale[] = [];

  const cleanup = installI18nSystemLocaleRefreshRuntime({
    enabled: true,
    addDocumentListener: null,
    addWindowListener: null,
    applyLocale: (locale) => {
      applied.push(locale);
    },
    currentLocale: 'en',
    detectSystemLocale: () => 'zh',
    getVisibilityState: () => 'visible',
  });

  cleanup();
  assert.deepEqual(applied, []);
});

test('i18n browser system-locale deps own document and window listener wiring', () => {
  const originalDocument = Object.getOwnPropertyDescriptor(globalThis, 'document');
  const originalWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');
  const documentListeners = new Map<string, () => void>();
  const windowListeners = new Map<string, () => void>();

  try {
    Object.defineProperty(globalThis, 'document', {
      configurable: true,
      value: {
        visibilityState: 'visible',
        addEventListener: (type: string, listener: () => void) => {
          documentListeners.set(type, listener);
        },
        removeEventListener: (type: string, listener: () => void) => {
          if (documentListeners.get(type) === listener) documentListeners.delete(type);
        },
      },
    });
    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: {
        addEventListener: (type: string, listener: () => void) => {
          windowListeners.set(type, listener);
        },
        removeEventListener: (type: string, listener: () => void) => {
          if (windowListeners.get(type) === listener) windowListeners.delete(type);
        },
      },
    });

    const deps = createBrowserI18nSystemLocaleRefreshRuntimeDeps({
      enabled: true,
      applyLocale: () => {},
      currentLocale: 'en',
      detectSystemLocale: () => 'zh',
    });
    const cleanup = installI18nSystemLocaleRefreshRuntime(deps);

    assert.equal(documentListeners.has('visibilitychange'), true);
    assert.equal(windowListeners.has('focus'), true);
    assert.equal(deps.getVisibilityState(), 'visible');

    cleanup();
    assert.equal(documentListeners.size, 0);
    assert.equal(windowListeners.size, 0);
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

test('i18n preference load timeout scheduling uses the injected timer host', () => {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: I18nPreferenceLoadTimeoutHost = {
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `i18n-timeout-${callbacks.length}`;
    },
  };

  let timeoutCount = 0;
  const cleanup = scheduleI18nPreferenceLoadTimeout({
    timerHost: host,
    onTimeout: () => {
      timeoutCount += 1;
    },
  });

  assert.deepEqual(delays, [I18N_PREFERENCE_LOAD_TIMEOUT_MS]);
  assert.equal(timeoutCount, 0);

  callbacks[0]?.();
  assert.equal(timeoutCount, 1);

  cleanup();
  assert.deepEqual(clearedHandles, ['i18n-timeout-1']);
});

test('i18n provider delegates system-locale refresh and preference-load timeout through browser-host seams', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/i18n.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/dates/i18nSystemLocale.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*applyBrowserLocaleDocumentAttributes,[\s\S]*createBrowserI18nPreferenceLoadTimeoutHost,[\s\S]*createBrowserI18nSystemLocaleRefreshRuntimeDeps,[\s\S]*installI18nSystemLocaleRefreshRuntime,[\s\S]*scheduleI18nPreferenceLoadTimeout,[\s\S]*\} from '\.\/dates\/i18nSystemLocale\.runtime';/s,
  );
  assert.match(source, /applyBrowserLocaleDocumentAttributes\(code\);/);
  assert.doesNotMatch(source, /document\.documentElement\.(lang|dir)/);
  assert.match(source, /const i18nPreferenceLoadTimeoutHost = createBrowserI18nPreferenceLoadTimeoutHost\(\);/);
  assert.match(
    source,
    /const cleanupPreferenceLoadTimeout = scheduleI18nPreferenceLoadTimeout\(\{[\s\S]*timerHost: i18nPreferenceLoadTimeoutHost,[\s\S]*onTimeout: \(\) => \{[\s\S]*i18n\.loadPreference\.timeout[\s\S]*fallbackToSystem\(\);[\s\S]*\},[\s\S]*\}\);/s,
  );
  assert.match(
    source,
    /installI18nSystemLocaleRefreshRuntime\(createBrowserI18nSystemLocaleRefreshRuntimeDeps\(\{[\s\S]*enabled: usingSystemLocale,[\s\S]*applyLocale,[\s\S]*currentLocale: locale,[\s\S]*detectSystemLocale,[\s\S]*\}\)\);/s,
  );
  assert.doesNotMatch(source, /addDocumentListener: typeof document/);
  assert.doesNotMatch(source, /addWindowListener: typeof window/);
  assert.doesNotMatch(source, /getVisibilityState: \(\) => \(typeof document/);
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);
  assert.doesNotMatch(source, /(?<!\.)\bclearTimeout\(/);

  assert.match(runtimeSource, /export function createBrowserI18nPreferenceLoadTimeoutHost\(\): I18nPreferenceLoadTimeoutHost/);
  assert.match(runtimeSource, /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('i18n runtime owns the browser preference-load timeout host wiring', () => {
  const host = createBrowserI18nPreferenceLoadTimeoutHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});
