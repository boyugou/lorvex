import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { formatShortcut, isPrimaryModifierPressed } from '../../../app/src/lib/shortcuts';

function withNavigator(
  navigatorValue: { userAgent: string; maxTouchPoints?: number } | undefined,
  run: () => void,
): void {
  const original = Object.getOwnPropertyDescriptor(globalThis, 'navigator');

  try {
    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      value: navigatorValue,
    });
    run();
  } finally {
    if (original) {
      Object.defineProperty(globalThis, 'navigator', original);
    } else {
      Reflect.deleteProperty(globalThis, 'navigator');
    }
  }
}

test('shortcuts use Apple glyphs for macOS and fall back to Apple without a navigator host', () => {
  withNavigator({ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0_0)' }, () => {
    assert.equal(formatShortcut(['Mod', 'Shift', 'K']), '⌘⇧K');
    assert.equal(isPrimaryModifierPressed({ metaKey: true, ctrlKey: false } as KeyboardEvent), true);
  });

  withNavigator(undefined, () => {
    assert.equal(formatShortcut(['Mod', 'Alt', 'K']), '⌘⌥K');
    assert.equal(isPrimaryModifierPressed({ metaKey: true, ctrlKey: false } as KeyboardEvent), true);
  });
});

test('shortcuts use Ctrl-style labels and primary modifier outside Apple runtimes', () => {
  withNavigator({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }, () => {
    assert.equal(formatShortcut(['Mod', 'Shift', 'K']), 'Ctrl+Shift+K');
    assert.equal(isPrimaryModifierPressed({ metaKey: true, ctrlKey: false } as KeyboardEvent), false);
    assert.equal(isPrimaryModifierPressed({ metaKey: false, ctrlKey: true } as KeyboardEvent), true);
  });
});

test('shortcuts facade delegates navigator access to the platform runtime seam', () => {
  const source = fs.readFileSync(path.join(process.cwd(), 'app/src/lib/shortcuts/index.ts'), 'utf8');

  assert.match(source, /readRuntimeNavigatorSnapshot/);
  assert.doesNotMatch(source, /\bnavigator\b/);
});
