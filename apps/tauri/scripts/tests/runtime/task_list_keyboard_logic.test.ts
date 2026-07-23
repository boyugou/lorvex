import assert from 'node:assert/strict';
import test from 'node:test';

import { priorityFromKeyboardKey } from '../../../app/src/lib/tasks/useTaskListKeyboard.logic';

test('priorityFromKeyboardKey accepts only canonical priority shortcut keys', () => {
  assert.equal(priorityFromKeyboardKey('1'), 1);
  assert.equal(priorityFromKeyboardKey('2'), 2);
  assert.equal(priorityFromKeyboardKey('3'), 3);

  assert.equal(priorityFromKeyboardKey('0'), null);
  assert.equal(priorityFromKeyboardKey('4'), null);
  assert.equal(priorityFromKeyboardKey('01'), null);
  assert.equal(priorityFromKeyboardKey('1.5'), null);
  assert.equal(priorityFromKeyboardKey('1e0'), null);
});
