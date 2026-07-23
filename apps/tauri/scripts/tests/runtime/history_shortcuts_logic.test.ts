import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getHistoryShortcutAction,
  resolveHistoryShortcutRoute,
  resolveUnhandledEditorHistoryShortcutRoute,
  type HistoryShortcutEventLike,
} from '../../../app/src/lib/historyShortcuts.logic';

function shortcutEvent(
  overrides: Partial<HistoryShortcutEventLike>,
): HistoryShortcutEventLike {
  return {
    altKey: false,
    ctrlKey: false,
    key: 'z',
    metaKey: false,
    shiftKey: false,
    ...overrides,
  };
}

test('history shortcuts: detect undo for mod-z without alt', () => {
  assert.equal(getHistoryShortcutAction(shortcutEvent({ metaKey: true, key: 'z' })), 'undo');
  assert.equal(getHistoryShortcutAction(shortcutEvent({ ctrlKey: true, key: 'Z' })), 'undo');
  assert.equal(getHistoryShortcutAction(shortcutEvent({ metaKey: true, altKey: true, key: 'z' })), null);
});

test('history shortcuts: detect redo for shift-mod-z and mod-y', () => {
  assert.equal(
    getHistoryShortcutAction(shortcutEvent({ ctrlKey: true, shiftKey: true, key: 'z' })),
    'redo',
  );
  assert.equal(getHistoryShortcutAction(shortcutEvent({ metaKey: true, key: 'y' })), 'redo');
  assert.equal(getHistoryShortcutAction(shortcutEvent({ metaKey: true, shiftKey: true, key: 'y' })), null);
});

test('history shortcuts: route editors ahead of native inputs and toast undo', () => {
  assert.equal(
    resolveHistoryShortcutRoute({
      action: 'undo',
      activeElementIgnoresShortcut: true,
      editorOwnsTarget: true,
      targetIgnoresShortcut: true,
    }),
    'editor',
  );
  assert.equal(
    resolveHistoryShortcutRoute({
      action: 'redo',
      activeElementIgnoresShortcut: false,
      editorOwnsTarget: false,
      targetIgnoresShortcut: true,
    }),
    'native',
  );
  assert.equal(
    resolveHistoryShortcutRoute({
      action: 'undo',
      activeElementIgnoresShortcut: false,
      editorOwnsTarget: false,
      targetIgnoresShortcut: false,
    }),
    'toast',
  );
  assert.equal(
    resolveHistoryShortcutRoute({
      action: 'redo',
      activeElementIgnoresShortcut: false,
      editorOwnsTarget: false,
      targetIgnoresShortcut: false,
    }),
    'none',
  );
});

test('history shortcuts: unhandled editor history falls back only for undo', () => {
  assert.equal(resolveUnhandledEditorHistoryShortcutRoute('undo'), 'toast');
  assert.equal(resolveUnhandledEditorHistoryShortcutRoute('redo'), 'none');
});
