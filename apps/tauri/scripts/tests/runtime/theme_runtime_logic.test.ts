import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserThemeDocumentHost,
  createBrowserThemeSystemPreferenceHost,
  shouldApplyNativeTheme,
} from '../../../app/src/lib/theme/runtime';

test('native theme reapply can be forced even when the logical theme matches the cached value', () => {
  assert.equal(shouldApplyNativeTheme({
    force: false,
    lastApplied: 'dark',
    nextNativeTheme: 'dark',
  }), false);

  assert.equal(shouldApplyNativeTheme({
    force: true,
    lastApplied: 'dark',
    nextNativeTheme: 'dark',
  }), true);

  assert.equal(shouldApplyNativeTheme({
    force: false,
    lastApplied: 'dark',
    nextNativeTheme: 'light',
  }), true);
});

test('theme browser system preference host fails closed when matchMedia is unavailable', () => {
  const originalWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');

  try {
    Object.defineProperty(globalThis, 'window', {
      configurable: true,
      value: {},
    });

    assert.equal(createBrowserThemeSystemPreferenceHost().readSystemPreference(), null);
  } finally {
    if (originalWindow) {
      Object.defineProperty(globalThis, 'window', originalWindow);
    } else {
      Reflect.deleteProperty(globalThis, 'window');
    }
  }
});

test('theme browser document host fails closed when document access throws', () => {
  const originalDocument = Object.getOwnPropertyDescriptor(globalThis, 'document');

  try {
    Object.defineProperty(globalThis, 'document', {
      configurable: true,
      get: () => {
        throw new Error('document unavailable');
      },
    });

    assert.equal(createBrowserThemeDocumentHost().getRoot(), null);
  } finally {
    if (originalDocument) {
      Object.defineProperty(globalThis, 'document', originalDocument);
    } else {
      Reflect.deleteProperty(globalThis, 'document');
    }
  }
});

test('theme runtime delegates browser document and media reads to runtime hosts', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/theme/runtime.ts'),
    'utf8',
  );

  assert.match(source, /createBrowserThemeDocumentHost/);
  assert.match(source, /createBrowserThemeSystemPreferenceHost/);
  assert.doesNotMatch(source, /typeof window === 'undefined'/);
  assert.doesNotMatch(source, /window\.matchMedia/);
  assert.doesNotMatch(source, /document\.documentElement/);
});
