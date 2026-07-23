import assert from 'node:assert/strict';
import test from 'node:test';

import { isEditableTarget } from '../../../app/src/lib/editableTarget';

function makeElement(tagName: string, opts: { parent?: object | null; contentEditable?: boolean } = {}) {
  const parent = opts.parent ?? null;
  return {
    tagName,
    parentElement: parent,
    parentNode: parent,
    isContentEditable: opts.contentEditable ?? false,
  };
}

test('isEditableTarget accepts direct editable form controls', () => {
  assert.equal(isEditableTarget(makeElement('input')), true);
  assert.equal(isEditableTarget(makeElement('textarea')), true);
  assert.equal(isEditableTarget(makeElement('select')), true);
});

test('isEditableTarget walks ancestors so nested contenteditable descendants still suppress shortcuts', () => {
  const host = makeElement('div', { contentEditable: true });
  const child = makeElement('span', { parent: host });
  const textNode = { nodeType: 3, parentElement: child, parentNode: child };

  assert.equal(isEditableTarget(child as EventTarget), true);
  assert.equal(isEditableTarget(textNode as EventTarget), true);
});

test('isEditableTarget returns false for non-editable surfaces', () => {
  const wrapper = makeElement('div');
  const child = makeElement('button', { parent: wrapper });

  assert.equal(isEditableTarget(child as EventTarget), false);
  assert.equal(isEditableTarget(null), false);
});
