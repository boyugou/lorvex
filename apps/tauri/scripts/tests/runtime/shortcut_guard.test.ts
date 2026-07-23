import assert from 'node:assert/strict';
import test from 'node:test';

import { shouldIgnoreShortcut } from '../../../app/src/lib/shortcutGuard';

function makeElement(
  tagName: string,
  opts: { parent?: object | null; contentEditable?: boolean; closestResult?: object | null } = {},
) {
  const parent = opts.parent ?? null;
  return {
    tagName,
    parentElement: parent,
    parentNode: parent,
    isContentEditable: opts.contentEditable ?? false,
    closest: () => opts.closestResult ?? null,
  };
}

test('shouldIgnoreShortcut suppresses nested contenteditable descendants and text-node targets', () => {
  const host = makeElement('DIV', { contentEditable: true });
  const child = makeElement('SPAN', { parent: host });
  const textNode = { nodeType: 3, parentElement: child, parentNode: child };

  assert.equal(shouldIgnoreShortcut(child as EventTarget), true);
  assert.equal(shouldIgnoreShortcut(textNode as EventTarget), true);
});

test('shouldIgnoreShortcut preserves interactive-role suppression via closest()', () => {
  const menuButton = makeElement('BUTTON', { closestResult: {} });
  assert.equal(shouldIgnoreShortcut(menuButton as EventTarget), true);
});

test('shouldIgnoreShortcut returns false for plain non-editable targets', () => {
  const div = makeElement('DIV');
  assert.equal(shouldIgnoreShortcut(div as EventTarget), false);
  assert.equal(shouldIgnoreShortcut(null), false);
});
