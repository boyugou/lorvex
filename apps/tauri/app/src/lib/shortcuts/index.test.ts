import { describe, expect, test } from 'vitest';

import {
  ariaKeyShortcutsForModChord,
  formatShortcutForPlatform,
} from '.';

describe('formatShortcutForPlatform', () => {
  test('uses Apple glyphs for Mod chords on Apple platforms', () => {
    expect(formatShortcutForPlatform(['Shift', 'Mod', '↵'], 'apple')).toBe('⇧⌘↵');
    expect(formatShortcutForPlatform(['Mod', '['], 'apple')).toBe('⌘[');
  });

  test('uses Control labels for Mod chords on non-Apple platforms', () => {
    expect(formatShortcutForPlatform(['Shift', 'Mod', '↵'], 'nonApple')).toBe('Shift+Ctrl+↵');
    expect(formatShortcutForPlatform(['Mod', '['], 'nonApple')).toBe('Ctrl+[');
  });
});

describe('ariaKeyShortcutsForModChord', () => {
  test('expands Mod chords to both Meta and Control shortcuts', () => {
    expect(ariaKeyShortcutsForModChord(['Mod', '['])).toBe('Meta+[ Control+[');
    expect(ariaKeyShortcutsForModChord(['Shift', 'Mod', 'Enter'])).toBe(
      'Shift+Meta+Enter Shift+Control+Enter',
    );
  });

  test('normalizes visual key tokens to ARIA key names', () => {
    expect(ariaKeyShortcutsForModChord(['Mod', '↵'])).toBe('Meta+Enter Control+Enter');
    expect(ariaKeyShortcutsForModChord(['Mod', 'Shift', '←'])).toBe(
      'Meta+Shift+ArrowLeft Control+Shift+ArrowLeft',
    );
  });
});
