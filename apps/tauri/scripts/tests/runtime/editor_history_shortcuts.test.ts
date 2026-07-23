import assert from 'node:assert/strict';
import test from 'node:test';

import {
  dispatchEditorHistoryShortcut,
  isEditorHistoryShortcutTarget,
} from '../../../app/src/lib/shortcuts/editorHistory';

test('editor history shortcuts stay inert when the DOM Node constructor is unavailable', () => {
  const previousNode = globalThis.Node;
  Reflect.deleteProperty(globalThis, 'Node');

  try {
    const target = {} as EventTarget;

    assert.equal(isEditorHistoryShortcutTarget(target), false);
    assert.equal(dispatchEditorHistoryShortcut('undo', target), false);
  } finally {
    if (previousNode === undefined) {
      Reflect.deleteProperty(globalThis, 'Node');
    } else {
      globalThis.Node = previousNode;
    }
  }
});
