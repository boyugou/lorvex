import assert from 'node:assert/strict';
import test from 'node:test';

import { resolveLocalePreference } from '../../../app/src/locales';

const originalNavigatorDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'navigator');

function withNavigator(
  value: { language?: string; languages?: string[] },
  run: () => void,
): void {
  Object.defineProperty(globalThis, 'navigator', {
    configurable: true,
    value,
  });

  try {
    run();
  } finally {
    if (originalNavigatorDescriptor) {
      Object.defineProperty(globalThis, 'navigator', originalNavigatorDescriptor);
    } else {
      Reflect.deleteProperty(globalThis, 'navigator');
    }
  }
}

test('resolveLocalePreference falls back to the detected system locale when preference is missing', () => {
  withNavigator({ language: 'zh-CN', languages: ['zh-CN', 'en-US'] }, () => {
    assert.deepEqual(resolveLocalePreference(null), {
      locale: 'zh',
      usingSystemLocale: true,
    });
  });
});

test('resolveLocalePreference falls back to the detected system locale when persisted language is invalid', () => {
  withNavigator({ language: 'fr-FR', languages: ['fr-FR', 'en-US'] }, () => {
    assert.deepEqual(resolveLocalePreference('"bogus"'), {
      locale: 'fr',
      usingSystemLocale: true,
    });
  });
});

test('resolveLocalePreference preserves explicit supported language preferences', () => {
  withNavigator({ language: 'zh-CN', languages: ['zh-CN', 'en-US'] }, () => {
    assert.deepEqual(resolveLocalePreference('"de"'), {
      locale: 'de',
      usingSystemLocale: false,
    });
  });
});
