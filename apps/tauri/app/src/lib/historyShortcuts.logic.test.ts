import { describe, expect, test } from 'vitest';

import {
  getHistoryShortcutAction,
  resolveHistoryShortcutRoute,
  resolveUnhandledEditorHistoryShortcutRoute,
  type HistoryShortcutEventLike,
} from './historyShortcuts.logic';

// Undo/Redo shortcut routing has subtle key+modifier rules:
//   * Cmd/Ctrl-Z          → undo
//   * Cmd/Ctrl-Shift-Z    → redo
//   * Cmd/Ctrl-Y          → redo  (Windows)
//   * Cmd/Ctrl-Shift-Y    → ignore (collides with browser's view-source on some)
//   * Alt-Z / plain Z      → ignore (the body would type a literal "z")
//
// And then the route the action takes depends on focus state:
//   * editor focused → handed to the rich-text editor's history stack
//   * focus is on a "native handles undo" element (input, textarea,
//     contenteditable that isn't ours) → fall through to the browser
//   * otherwise: undo → "toast" (mutation-undo via the global toaster);
//                redo → "none" (no redo system outside the editor)
//
// These tests pin every triple of (key, modifier set, focus state) so
// a refactor of the shortcut branching can't silently regress to "all
// Cmd-Z is undo" or "Cmd-Shift-Y is redo".

const evt = (overrides: Partial<HistoryShortcutEventLike>): HistoryShortcutEventLike => ({
  altKey: false,
  ctrlKey: false,
  key: 'z',
  metaKey: false,
  shiftKey: false,
  ...overrides,
});

describe('getHistoryShortcutAction', () => {
  test('Cmd-Z → undo', () => {
    expect(getHistoryShortcutAction(evt({ metaKey: true, key: 'z' }))).toBe('undo');
  });

  test('Ctrl-Z → undo', () => {
    expect(getHistoryShortcutAction(evt({ ctrlKey: true, key: 'z' }))).toBe('undo');
  });

  test('Cmd-Shift-Z → redo', () => {
    expect(getHistoryShortcutAction(evt({ metaKey: true, shiftKey: true, key: 'z' }))).toBe('redo');
  });

  test('Ctrl-Y → redo (Windows convention)', () => {
    expect(getHistoryShortcutAction(evt({ ctrlKey: true, key: 'y' }))).toBe('redo');
  });

  test('Cmd-Y → redo (mac, even though browsers historically use it for History; the app overrides)', () => {
    expect(getHistoryShortcutAction(evt({ metaKey: true, key: 'y' }))).toBe('redo');
  });

  test('Cmd-Shift-Y → null (not a defined shortcut; release to browser)', () => {
    expect(getHistoryShortcutAction(evt({ metaKey: true, shiftKey: true, key: 'y' }))).toBeNull();
  });

  test('plain Z (no modifier) → null (avoid stealing typed text)', () => {
    expect(getHistoryShortcutAction(evt({ key: 'z' }))).toBeNull();
  });

  test('Alt-Cmd-Z → null (Alt disables history shortcut family)', () => {
    expect(getHistoryShortcutAction(evt({ altKey: true, metaKey: true, key: 'z' }))).toBeNull();
    expect(getHistoryShortcutAction(evt({ altKey: true, ctrlKey: true, key: 'y' }))).toBeNull();
  });

  test('case-insensitive on the key (uppercase Z still routes)', () => {
    expect(getHistoryShortcutAction(evt({ metaKey: true, key: 'Z' }))).toBe('undo');
    expect(getHistoryShortcutAction(evt({ metaKey: true, shiftKey: true, key: 'Z' }))).toBe('redo');
  });

  test('unrelated keys with Cmd/Ctrl held → null (e.g. Cmd-S, Ctrl-A)', () => {
    expect(getHistoryShortcutAction(evt({ metaKey: true, key: 's' }))).toBeNull();
    expect(getHistoryShortcutAction(evt({ ctrlKey: true, key: 'a' }))).toBeNull();
  });
});

describe('resolveHistoryShortcutRoute', () => {
  const baseFocus = {
    editorOwnsTarget: false,
    targetIgnoresShortcut: false,
    activeElementIgnoresShortcut: false,
  };

  test('editor owns target → "editor" wins regardless of action', () => {
    expect(resolveHistoryShortcutRoute({
      action: 'undo',
      ...baseFocus,
      editorOwnsTarget: true,
    })).toBe('editor');
    expect(resolveHistoryShortcutRoute({
      action: 'redo',
      ...baseFocus,
      editorOwnsTarget: true,
    })).toBe('editor');
  });

  test('native handles shortcut (target ignores) → "native"', () => {
    expect(resolveHistoryShortcutRoute({
      action: 'undo',
      ...baseFocus,
      targetIgnoresShortcut: true,
    })).toBe('native');
  });

  test('active element ignores shortcut (input focused) → "native"', () => {
    expect(resolveHistoryShortcutRoute({
      action: 'redo',
      ...baseFocus,
      activeElementIgnoresShortcut: true,
    })).toBe('native');
  });

  test('default focus + undo → "toast" (global mutation undo)', () => {
    expect(resolveHistoryShortcutRoute({
      action: 'undo',
      ...baseFocus,
    })).toBe('toast');
  });

  test('default focus + redo → "none" (no redo outside editor)', () => {
    expect(resolveHistoryShortcutRoute({
      action: 'redo',
      ...baseFocus,
    })).toBe('none');
  });
});

describe('resolveUnhandledEditorHistoryShortcutRoute', () => {
  test('undo → "toast" (consumed by toaster), redo → "none" (drop)', () => {
    expect(resolveUnhandledEditorHistoryShortcutRoute('undo')).toBe('toast');
    expect(resolveUnhandledEditorHistoryShortcutRoute('redo')).toBe('none');
  });
});
